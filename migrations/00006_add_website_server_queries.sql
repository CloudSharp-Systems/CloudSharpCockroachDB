-- +goose Up
CREATE VIEW products.v_server_usage AS
WITH serv AS (SELECT * FROM products.tb_server WHERE status <> 'REMOVED' OR last_service_date > current_date - INTERVAL '6 MONTH'),
     host AS (SELECT * FROM network.tb_website_host WHERE serial_no IN (SELECT serial_no FROM serv)),
     webs AS (SELECT * FROM network.tb_website WHERE site_id IN (SELECT site_id FROM host))
SELECT
    s.serial_no,
    s.status AS server_status,
    s.net_load_capacity,
    s.server_spec,
    s.cpu,
    s.ram,
    s.storage,
    s.registration_date,
    s.last_service_date,
    s.owned_by AS server_owned_by,
    s.location_code,
    w.site_id,
    w.app_id,
    w.domain_name,
    w.site_name,
    w.load_balancing_algorithm,
    w.is_enabled AS is_site_enabled,
    w.owned_by AS site_owned_by,
    h.host_ip,
    h.port,
    h.status AS host_status,
    h.error_measurement_algorithm,
    h.error_rate,
    h.measured_time
FROM serv s
LEFT JOIN host h ON s.serial_no = h.serial_no
LEFT JOIN webs w ON h.site_id = w.site_id;


-- +goose StatementBegin
CREATE PROCEDURE network.reset_server_capacity(
    target_host_ip STRING,
    target_capacity INT,
    target_edit_by STRING,
    preset_error_rate FLOAT DEFAULT 0.0
)
LANGUAGE SQL AS $$
    -- Step 1: Insert existing user sessions into the session history log
    INSERT INTO network.tb_user_session_history_log (
        session_id, client_ip, thread_id, host_ip, resource_unit,
        client_location, requested_time, resource_size, edit_by,
        connected_time, disconnected_time
    )
    SELECT
        session_id, client_ip, thread_id, host_ip, resource_unit,
        client_location, requested_time, resource_size, edit_by,
        edit_time AS connected_time, CURRENT_TIMESTAMP AS disconnected_time
    FROM network.tb_user_session
    WHERE host_ip = target_host_ip;

    -- Step 2: Delete user sessions for the specified host
    DELETE FROM network.tb_user_session WHERE host_ip = target_host_ip;

    -- Step 3: Update server capacity in the TB_SERVER table
    UPDATE products.tb_server SET net_load_capacity = target_capacity, edit_by = target_edit_by, edit_time = CURRENT_TIMESTAMP
    WHERE serial_no = (
        SELECT serial_no FROM network.tb_website_host
        WHERE host_ip = target_host_ip LIMIT 1
    );

    -- Step 4: Update the preset error rate in the TB_APP_DATA_CONTROL table
    UPDATE applications.tb_app_data_control
    SET control_value = CAST(preset_error_rate AS STRING), edit_by = target_edit_by, edit_date = CURRENT_TIMESTAMP
    WHERE app_id = 'CloudSharpSystemsWeb'
      AND control_name = 'LOAD_BALANCING_ALGORITHM'
      AND control_type = 'WEIGHTED_FAULT_AVOIDANCE'
      AND control_level = '__PRESET_ERROR_RATE_' || target_host_ip;

$$;
-- +goose StatementEnd




-- +goose Down
DROP PROCEDURE IF EXISTS network.reset_server_capacity;

DROP VIEW IF EXISTS products.v_server_usage;
