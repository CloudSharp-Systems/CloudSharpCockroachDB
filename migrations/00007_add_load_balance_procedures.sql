-- +goose Up


-- +goose StatementBegin
CREATE PROCEDURE network.load_balance_validate_load_cache(
    target_site_id STRING,
    max_cache_load INT,
    is_reset CHAR(1) DEFAULT 'N'
)
LANGUAGE PLpgSQL AS $$
DECLARE
    target_app_id STRING := 'CloudSharpSystemsWeb';
    data_control_name STRING := 'LOAD_BALANCING_ALGORITHM';
    algorithm_type STRING;
    load_cache_str STRING := 'LOAD_CACHE_';
    invalidation_timeout FLOAT := 0.0;
BEGIN
    -- Fetch the algorithm type for the specified site
    SELECT load_balancing_algorithm INTO algorithm_type
    FROM network.tb_website WHERE site_id = target_site_id LIMIT 1;

    -- Fetch the invalidation timeout for the specified algorithm
    SELECT control_value::FLOAT INTO invalidation_timeout
    FROM applications.v_app_data_control
    WHERE app_id = target_app_id AND control_name = data_control_name AND control_type = algorithm_type AND control_level = 'INVALIDATION_TIMEOUT'
          AND is_app_enabled = 'Y' AND is_control_enabled = 'Y';

    -- Invalidate outdated or reset cache entries
    UPDATE applications.tb_app_data_control
    SET control_value = '0', is_enabled = 'N', edit_by = target_app_id, edit_date = CURRENT_TIMESTAMP
    WHERE app_id = target_app_id AND control_name = data_control_name AND control_type = algorithm_type AND control_level LIKE load_cache_str || '%'
          AND control_level IN (SELECT load_cache_str || host_ip FROM network.tb_website_host WHERE site_id = target_site_id)
          AND is_enabled = 'Y'
          AND (is_reset = 'Y' OR edit_date < CURRENT_TIMESTAMP - (invalidation_timeout * INTERVAL '1 hour'));

    -- Reduce load numbers for overloaded cache entries
    IF EXISTS (
        SELECT 1 FROM applications.tb_app_data_control
        WHERE app_id = target_app_id AND control_name = data_control_name AND control_type = algorithm_type AND control_level LIKE load_cache_str || '%'
              AND control_level IN (SELECT load_cache_str || host_ip FROM network.tb_website_host WHERE site_id = target_site_id)
              AND is_enabled = 'Y' AND control_value::FLOAT > max_cache_load
    ) THEN
        UPDATE applications.tb_app_data_control
        SET control_value = (control_value::FLOAT - max_cache_load::FLOAT)::STRING, edit_by = target_app_id, edit_date = CURRENT_TIMESTAMP
        WHERE app_id = target_app_id AND control_name = data_control_name AND control_type = algorithm_type AND control_level LIKE load_cache_str || '%'
	      AND control_level IN (SELECT load_cache_str || host_ip FROM network.tb_website_host WHERE site_id = site_id)
              AND is_enabled = 'Y';
    END IF;

    -- Add new active hosts to the cache
    INSERT INTO applications.tb_app_data_control (
        app_id, control_name, control_type, control_level, control_value,
        control_note, is_enabled, edit_by, edit_date
    )
    SELECT target_app_id, data_control_name, algorithm_type, load_cache_str || host_ip, '0',
           'Cached load for application host ' || host_ip, 'Y', target_app_id, CURRENT_TIMESTAMP
    FROM network.tb_website_host WHERE site_id = target_site_id
         AND network.is_host_responsive('RUNNING', status) = 'Y' AND host_ip NOT IN (
            SELECT substring(control_level, char_length(load_cache_str) + 1)
            FROM applications.v_app_data_control
            WHERE app_id = target_app_id AND control_name = data_control_name AND control_type = algorithm_type
                  AND control_level LIKE load_cache_str || '%'
                  AND is_app_enabled = 'Y'
         );
END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE network.load_balance_reset(
    target_site_id STRING,
    algorithm STRING,
    max_search_count INT,
    target_edit_by STRING
)
LANGUAGE PLpgSQL AS $$
DECLARE
    old_algorithm STRING := NULL;
    load_capacity INT := 0;
    max_cache_load INT := 1000;
    valid_alg CHAR(1) := 'N';
BEGIN
    -- 1. Fetch the current algorithm
    SELECT load_balancing_algorithm INTO old_algorithm FROM network.tb_website
    WHERE site_id = target_site_id LIMIT 1;

    IF old_algorithm IS NULL THEN old_algorithm := 'NONE'; END IF;

    -- Convert algorithm to uppercase
    algorithm := UPPER(algorithm);

    -- Reset caches for WEIGHTED_ROUND_ROBIN
    IF old_algorithm = 'WEIGHTED_ROUND_ROBIN' THEN
        SELECT net_load_capacity INTO load_capacity FROM network.get_server_load(target_site_id)
        AS f(site_id STRING, serial_no STRING, host_ip STRING, port STRING, server_status STRING, ip_status STRING, net_load_capacity INT, session_count INT, resource_load INT, server_spec STRING, storage STRING, registration_date DATE, last_service_date DATE, location_code STRING, rack_code STRING)
        WHERE network.is_host_responsive(server_status, ip_status) = 'Y'
        ORDER BY net_load_capacity DESC LIMIT 1;

        UPDATE applications.tb_app_data_control
        SET control_value = '1', edit_by = target_edit_by, edit_date = CURRENT_TIMESTAMP
        WHERE app_id = 'CloudSharpSystemsWeb' AND control_name = 'LOAD_BALANCING_ALGORITHM' AND control_type = 'WEIGHTED_ROUND_ROBIN'
              AND control_level = 'CURRENT_INDEX' AND is_enabled = 'Y';

        UPDATE applications.tb_app_data_control
        SET control_value = '0', edit_by = target_edit_by, edit_date = CURRENT_TIMESTAMP
        WHERE app_id = 'CloudSharpSystemsWeb' AND control_name = 'LOAD_BALANCING_ALGORITHM' AND control_type = 'WEIGHTED_ROUND_ROBIN'
              AND control_level = 'CURRENT_LOAD' AND is_enabled = 'Y';

        UPDATE applications.tb_app_data_control
        SET control_value = (load_capacity / 10)::INT::STRING, edit_by = target_edit_by, edit_date = CURRENT_TIMESTAMP
        WHERE app_id = 'CloudSharpSystemsWeb' AND control_name = 'LOAD_BALANCING_ALGORITHM' AND control_type = 'WEIGHTED_ROUND_ROBIN'
              AND control_level = 'CURRENT_MAX_WEIGHT' AND is_enabled = 'Y';
    END IF;

    -- Reset caches for LEAST_CONNECTIONS or WEIGHTED_FAULT_AVOIDANCE
    IF old_algorithm IN ('LEAST_CONNECTIONS', 'WEIGHTED_FAULT_AVOIDANCE') THEN
        CALL network.load_balance_validate_load_cache(target_site_id, max_cache_load, 'Y');
    END IF;

    -- Reset IPV6 Global Cache

    -- Validate new algorithm
    IF EXISTS (
        SELECT 1 FROM applications.tb_app_data_control
        WHERE control_name = 'LOAD_BALANCING_ALGORITHM' AND control_type = 'ALGORITHM_TYPE' AND control_value = algorithm
        LIMIT 1
    ) THEN valid_alg := 'Y'; END IF;

    IF valid_alg != 'Y' THEN
        algorithm := 'NONE';
        -- Optionally raise an error
        -- RAISE EXCEPTION '% is not a valid implemented load balancing algorithm!', algorithm;
    END IF;

    -- Update the algorithm in the website table
    UPDATE network.tb_website SET load_balancing_algorithm = algorithm, edit_by = target_edit_by, edit_time = CURRENT_TIMESTAMP
    WHERE site_id = target_site_id;
END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE network.load_balance_none(
    target_site_id STRING,
    client_ip STRING,
    client_thread_id STRING,
    resource_size INT,
    OUT host_ip STRING,
    OUT resource_unit INT
)
LANGUAGE PLpgSQL AS $$
BEGIN
    -- Initialize the output variable
    host_ip := NULL;

    -- Fetch the first responsive host IP
    SELECT target_host_ip INTO host_ip
    FROM network.get_server_load(target_site_id)
    AS f(site_id STRING, serial_no STRING, target_host_ip STRING, port STRING, server_status STRING, ip_status STRING, net_load_capacity INT, session_count INT, resource_load INT, server_spec STRING, storage STRING, registration_date DATE, last_service_date DATE, location_code STRING, rack_code STRING)
    WHERE network.is_host_responsive(server_status, ip_status) = 'Y'
    LIMIT 1;

    -- Set the resource unit based on host_ip availability
    IF host_ip IS NULL THEN
        resource_unit := -1;
    ELSE
        resource_unit := 1;
    END IF;

END;
$$;
-- +goose StatementEnd





-- +goose Down
DROP PROCEDURE IF EXISTS network.load_balance_none;
DROP PROCEDURE IF EXISTS network.load_balance_reset;
DROP PROCEDURE IF EXISTS network.load_balance_validate_load_cache;
