-- +goose Up
CREATE SCHEMA interfaces;


CREATE TABLE interfaces.tb_website_menu_header (
    header_id STRING(100) DEFAULT experimental_strftime(current_timestamp(), '%Y%m%d%H%M%S') || '_' || gen_random_uuid() NOT NULL,
    site_id STRING(100) NOT NULL,
    parent_header_id STRING(100),
    user_id STRING(100) NOT NULL,
    menu_name STRING(100) NOT NULL,
    display_name STRING(100) NOT NULL,
    is_enabled CHAR(1) CHECK (is_enabled = 'N' OR is_enabled = 'Y'),
    edit_by STRING(100) NOT NULL,
    edit_time TIMESTAMP DEFAULT current_timestamp() NOT NULL,
    PRIMARY KEY (header_id),
    UNIQUE (header_id, menu_name),
    CONSTRAINT fk_site_id FOREIGN KEY (site_id) REFERENCES network.tb_website (site_id)
);

CREATE TABLE interfaces.tb_website_menu_item (
    header_id STRING(100) NOT NULL,
    item_name STRING(100) NOT NULL,
    display_name STRING(100) NOT NULL,
    route_type STRING(50),
    route STRING NOT NULL,
    icon STRING NOT NULL,
    ranking INT NOT NULL,
    is_enabled CHAR(1) CHECK (is_enabled = 'N' OR is_enabled = 'Y'),
    edit_by STRING(100) NOT NULL,
    edit_time TIMESTAMP DEFAULT current_timestamp() NOT NULL,
    PRIMARY KEY (header_id, item_name),
    CHECK (route_type = 'ASSET' OR route_type = 'PAGE' OR route_type = 'HTTP' OR route_type = 'MENU'),
    CONSTRAINT fk_header_id FOREIGN KEY (header_id) REFERENCES interfaces.tb_website_menu_header (header_id)
);





CREATE TYPE interfaces.rec_menu_item AS (
	menu_display_name STRING(100),
	menu_ranking INT,
	item_name STRING(100),
	display_name STRING(100),
	route_type STRING(50),
	route STRING,
	icon STRING,
	ranking INT
);

-- +goose StatementBegin
CREATE FUNCTION interfaces.get_menu_items_by_menu(target_site_id STRING, target_menu_name STRING, target_user_id STRING)
RETURNS SETOF interfaces.rec_menu_item LANGUAGE SQL AS $$
    SELECT
        menu_header.display_name AS menu_display_name,
        -1 AS menu_ranking,
        menu_item.item_name,
        menu_item.display_name,
        menu_item.route_type,
        menu_item.route,
        menu_item.icon,
        menu_item.ranking
    FROM (
        SELECT * FROM interfaces.tb_website_menu_header
        WHERE site_id = target_site_id AND menu_name = target_menu_name AND user_id = target_user_id AND is_enabled = 'Y'
    ) menu_header
    INNER JOIN interfaces.tb_website_menu_item AS menu_item ON menu_header.header_id = menu_item.header_id
    WHERE menu_item.is_enabled = 'Y';
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE FUNCTION interfaces.get_submenu_items_by_menu(target_site_id STRING, target_menu_name STRING, target_user_id STRING)
RETURNS SETOF interfaces.rec_menu_item LANGUAGE SQL AS $$
SELECT
    menu_header.display_name AS menu_display_name,
    menu_header.ranking AS menu_ranking,
    menu_item.item_name,
    menu_item.display_name,
    menu_item.route_type,
    menu_item.route,
    menu_item.icon,
    menu_item.ranking --AS item_ranking
FROM (
    SELECT h.header_id, h.display_name, main_menu.ranking
    FROM interfaces.tb_website_menu_header h
    INNER JOIN (
        SELECT * FROM INTERFACES.GET_MENU_ITEMS_BY_MENU(target_site_id, target_menu_name, target_user_id)
    ) main_menu
    ON h.header_id = main_menu.route
    WHERE h.is_enabled = 'Y'
) menu_header
LEFT JOIN interfaces.tb_website_menu_item menu_item
ON menu_header.header_id = menu_item.header_id AND menu_item.is_enabled = 'Y';
$$;
-- +goose StatementEnd




-- +goose StatementBegin
CREATE PROCEDURE interfaces.validate_website_menu_route(route_type STRING, route STRING)
LANGUAGE PLpgSQL AS $$
DECLARE
    valid CHAR(1);
    validator STRING;
    sql_query STRING;
BEGIN
    -- For cockroach DB, dynamic sql execution is not yet supported. Implement this in the server code, and invoke in impacted area.
    -- Fetch the validation logic from the control table

    SELECT control_value INTO validator
    FROM applications.tb_app_data_control
    WHERE app_id = 'CloudSharpVisualDashboard'
      AND control_name = 'WEBSITE_MENU_CONFIG'
      AND control_type = 'ROUTE_VALIDATION_FUNC'
      AND control_level = route_type
      AND is_enabled = 'Y'
    LIMIT 1;

    -- If no validation logic is found, raise an exception
    IF validator IS NULL OR validator = '' THEN
        RAISE EXCEPTION 'Path type not recognized!';
    END IF;


    /*
    -- Build the dynamic validation SQL
    sql_query := 'SELECT ' || validator;

    -- Execute the dynamic SQL and store the result
    EXECUTE sql_query INTO valid USING route;

    -- If the validation fails, raise an exception
    IF valid <> 'Y' THEN
        RAISE EXCEPTION 'Invalid path!';
    END IF;
    */

END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE interfaces.add_website_menu_item(
    menu_header_id STRING,
    target_item_name STRING,
    item_display_name STRING,
    target_route_type STRING,
    target_route STRING,
    target_icon STRING,
    target_edit_by STRING
) LANGUAGE PLpgSQL AS $$
DECLARE
    target_is_enabled CHAR(1) := NULL;
    new_item_rank INT;
BEGIN
    -- Validate item name
    SELECT is_enabled INTO target_is_enabled FROM interfaces.tb_website_menu_item
    WHERE header_id = menu_header_id AND item_name = target_item_name
    LIMIT 1;

    IF target_is_enabled IS NULL THEN target_is_enabled := ''; END IF;

    IF target_is_enabled = 'Y' THEN
        RAISE EXCEPTION 'Item ID is already taken!';
    END IF;

    -- Validate route
    CALL interfaces.validate_website_menu_route(target_route_type, target_route);

    -- Compute ranking
    SELECT COALESCE(MAX(ranking), 0) INTO new_item_rank
    FROM interfaces.tb_website_menu_item
    WHERE header_id = menu_header_id;

    IF new_item_rank < 0 THEN
        new_item_rank := 0; -- Set as active item if current menu only contains inactive (ranking = -1) ones.
    END IF;

    IF target_is_enabled = 'N' THEN
        -- Update existing inactive item
        UPDATE interfaces.tb_website_menu_item
        SET
            display_name = item_display_name,
            route_type = target_route_type,
            route = target_route,
            icon = target_icon,
            ranking = new_item_rank + 1,
            is_enabled = 'Y',
            edit_by = target_edit_by,
            edit_time = CURRENT_TIMESTAMP
        WHERE header_id = menu_header_id AND item_name = target_item_name;
    ELSE
        -- Insert new item
        INSERT INTO interfaces.tb_website_menu_item (
            header_id, item_name, display_name, route_type, route, icon, ranking, is_enabled, edit_by, edit_time
        )
        VALUES (
            menu_header_id,
            target_item_name,
            item_display_name,
            target_route_type,
            target_route,
            target_icon,
            new_item_rank + 1,
            'Y',
            target_edit_by,
            CURRENT_TIMESTAMP
        );
    END IF;
END;
$$;
-- +goose StatementEnd




-- +goose Down
DROP PROCEDURE IF EXISTS interfaces.add_website_menu_item;
DROP PROCEDURE IF EXISTS interfaces.validate_website_menu_route;

DROP FUNCTION IF EXISTS interfaces.get_submenu_items_by_menu;
DROP FUNCTION IF EXISTS interfaces.get_menu_items_by_menu;
DROP TYPE IF EXISTS interfaces.rec_menu_item;

DROP TABLE IF EXISTS interfaces.tb_website_menu_item;
DROP TABLE IF EXISTS interfaces.tb_website_menu_header;

DROP SCHEMA IF EXISTS interfaces;

