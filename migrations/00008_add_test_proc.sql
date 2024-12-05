-- +goose Up

-- +goose StatementBegin
CREATE OR REPLACE PROCEDURE network.test_temp_table(
    target_site_id STRING,
    client_ip STRING,
    client_thread_id STRING,
    resource_size INT,
    OUT host_ip STRING,
    OUT resource_unit INT
)
LANGUAGE PLpgSQL AS $$
DECLARE
    target_app_id STRING := 'CloudSharpSystemsWeb';
    data_control_name STRING := 'LOAD_BALANCING_ALGORITHM';
    algorithm_type STRING := 'WEIGHTED_ROUND_ROBIN';
    weight_scale FLOAT := 0.1;

    current_max_weight INT;
    current_load INT;
    current_index INT;

    data_control JSON[];

BEGIN
    -- Initialize output
    host_ip := NULL;

    SELECT ARRAY(
        SELECT JSON_BUILD_OBJECT('k', control_level, 'v', control_value)
        FROM applications.v_app_data_control
        WHERE control_name = data_control_name AND app_id = target_app_id AND control_type = algorithm_type
          AND is_app_enabled = 'Y' AND is_control_enabled = 'Y'
    )
    INTO data_control;

    SELECT (c->'v')::INT INTO current_index FROM UNNEST(data_control) AS c WHERE (c->'k')::STRING = 'CURRENT_INDEX';
    SELECT (c->'v')::INT INTO current_max_weight FROM UNNEST(data_control) AS c WHERE (c->'k')::STRING = 'CURRENT_MAX_WEIGHT';
    SELECT (c->'v')::INT INTO current_load FROM UNNEST(data_control) AS c WHERE (c->'k')::STRING = 'CURRENT_LOAD';

END;
$$;
-- +goose StatementEnd




-- +goose Down
DROP PROCEDURE IF EXISTS network.test_temp_table;
