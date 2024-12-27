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


-- +goose StatementBegin
CREATE OR REPLACE PROCEDURE network.load_balance_least_connections (
    target_site_id STRING,
    client_ip STRING,
    client_thread_id STRING,
    resource_size INT,
    OUT host_ip VARCHAR(100),
    OUT resource_unit INT
)
LANGUAGE PLpgSQL AS $$
DECLARE
    target_app_id STRING := 'CloudSharpSystemsWeb';
    data_control_name STRING := 'LOAD_BALANCING_ALGORITHM';
    algorithm_type STRING := 'LEAST_CONNECTIONS';
    load_cache_str STRING := 'LOAD_CACHE_';
    max_cache_load INT := 1000;
BEGIN
    -- Initialize output parameter
    host_ip := NULL;

    -- Call validation procedure
    CALL network.load_balance_validate_load_cache(target_site_id, max_cache_load);

    -- Select the host IP with the least connection load
    SELECT RIGHT(control_level, LENGTH(control_level) - LENGTH(load_cache_str)) INTO host_ip
    FROM applications.tb_app_data_control
    WHERE app_id = target_app_id
      AND control_name = data_control_name
      AND control_type = algorithm_type
      AND control_level IN (
          SELECT load_cache_str || f.host_ip
          FROM network.get_server_load(target_site_id)
          AS f(site_id STRING, serial_no STRING, host_ip STRING, port STRING, server_status STRING, ip_status STRING, net_load_capacity INT, session_count INT, resource_load INT, server_spec STRING, storage STRING, registration_date DATE, last_service_date DATE, location_code STRING, rack_code STRING)
          WHERE network.is_host_responsive(f.server_status, f.ip_status) = 'Y'
            AND f.net_load_capacity - f.resource_load > resource_size
      )
    ORDER BY control_value::FLOAT ASC
    LIMIT 1;

    -- Update the load value for the selected host
    IF host_ip IS NOT NULL THEN
        UPDATE applications.tb_app_data_control
        SET control_value = (control_value::FLOAT + resource_size::FLOAT)::STRING, is_enabled = 'Y', edit_by = target_app_id, edit_date = current_timestamp
        WHERE app_id = target_app_id
          AND control_name = data_control_name
          AND control_type = algorithm_type
          AND control_level = load_cache_str || host_ip;
    END IF;

    -- Set the resource unit output parameter
    IF host_ip IS NULL THEN
        resource_unit := -1;
    ELSE
        resource_unit := 1;
    END IF;
END;
$$;
-- +goose StatementEnd



--CREATE TYPE applications.data_control_kv AS (k STRING, v STRING);
--CREATE TYPE network.server_load AS (site_id STRING, serial_no STRING, host_ip STRING, port STRING, server_status STRING, ip_status STRING, net_load_capacity INT, session_count INT, resource_load INT, server_spec STRING, storage STRING, registration_date DATE, last_service_date DATE, location_code STRING, rack_code STRING, row_id INT);
-- +goose StatementBegin
CREATE OR REPLACE PROCEDURE network.load_balance_weighted_round_robin(
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

    data_control JSON[]; --applications.data_control_kv[];
    load_dist JSON[]; --network.server_load[];

BEGIN
    -- Initialize output
    host_ip := NULL;

    SELECT ARRAY(
        SELECT JSON_BUILD_OBJECT(
		'k', control_level,
		'v', control_value
	) FROM applications.v_app_data_control
        WHERE control_name = data_control_name AND app_id = target_app_id AND control_type = algorithm_type
          AND is_app_enabled = 'Y' AND is_control_enabled = 'Y'
    )
    INTO data_control;

    SELECT (c->'v')::INT INTO current_index FROM UNNEST(data_control) AS c WHERE (c->'k')::STRING = 'CURRENT_INDEX';
    SELECT (c->'v')::INT INTO current_max_weight FROM UNNEST(data_control) AS c WHERE (c->'k')::STRING = 'CURRENT_MAX_WEIGHT';
    SELECT (c->'v')::INT INTO current_load FROM UNNEST(data_control) AS c WHERE (c->'k')::STRING = 'CURRENT_LOAD';

    -- Step 3.1: Select host IP based on load distribution
    IF current_load < current_max_weight THEN
        SELECT cte.host_ip INTO host_ip
        FROM (
            SELECT *, ROW_NUMBER() OVER (ORDER BY f.serial_no, f.net_load_capacity DESC) AS rn
            FROM network.get_server_load(target_site_id)
            AS f(site_id STRING, serial_no STRING, host_ip STRING, port STRING, server_status STRING, ip_status STRING, net_load_capacity INT, session_count INT, resource_load INT, server_spec STRING, storage STRING, registration_date DATE, last_service_date DATE, location_code STRING, rack_code STRING)
            WHERE network.is_host_responsive(f.server_status, f.ip_status) = 'Y'
        ) cte
        WHERE cte.rn = current_index AND cte.net_load_capacity - cte.resource_load > resource_size;

        current_load := current_load + resource_size;
    END IF;

    -- Step 3.2: If the current max weight cannot allocate for the new resource, find the next host IP
    IF host_ip IS NULL THEN

        SELECT ARRAY(
            SELECT JSON_BUILD_OBJECT(
		'serial_no', serial_no,
		't_host_ip', t_host_ip,
		'net_load_capacity', net_load_capacity,
		'resource_load', resource_load,
		'row_id', ROW_NUMBER() OVER (ORDER BY f.serial_no, f.net_load_capacity DESC)
	    ) FROM network.get_server_load(target_site_id)
            AS f(site_id STRING, serial_no STRING, t_host_ip STRING, port STRING, server_status STRING, ip_status STRING, net_load_capacity INT, session_count INT, resource_load INT, server_spec STRING, storage STRING, registration_date DATE, last_service_date DATE, location_code STRING, rack_code STRING)
            WHERE network.is_host_responsive(f.server_status, f.ip_status) = 'Y'
        ) INTO load_dist;

        SELECT t_host_ip, row_id, (net_load_capacity::FLOAT * weight_scale)::INT
        INTO host_ip, current_index, current_max_weight
        FROM (
            SELECT * FROM (
                SELECT (ld->'t_host_ip')::STRING AS t_host_ip, (ld->'row_id')::INT AS row_id, (ld->'net_load_capacity')::INT AS net_load_capacity
		FROM UNNEST(load_dist) AS ld
                WHERE (ld->'row_id')::INT > current_index AND (ld->'net_load_capacity')::INT - (ld->'resource_load')::INT > resource_size
                ORDER BY (ld->'serial_no')::STRING, (ld->'net_load_capacity')::INT DESC LIMIT 1
            ) candidate_up
            UNION ALL
            SELECT * FROM (
                SELECT (ld->'t_host_ip')::STRING AS t_host_ip, (ld->'row_id')::INT AS row_id, (ld->'net_load_capacity')::INT AS net_load_capacity
		FROM UNNEST(load_dist) AS ld
                WHERE (ld->'row_id')::INT <= current_index AND (ld->'net_load_capacity')::INT - (ld->'resource_load')::INT > resource_size
                ORDER BY (ld->'serial_no')::STRING, (ld->'net_load_capacity')::INT DESC LIMIT 1
            ) candidate_down
        ) next_host_candidate
        ORDER BY row_id DESC;

        current_load := resource_size;
    END IF;

    -- Step 3.3: Update round robin load balancer cache data
    IF host_ip IS NOT NULL THEN
        resource_unit := 1;

        UPDATE applications.tb_app_data_control SET control_value = current_index::STRING
        WHERE control_name = data_control_name AND app_id = target_app_id AND control_type = algorithm_type AND control_level = 'CURRENT_INDEX'
          AND is_enabled = 'Y';

        UPDATE applications.tb_app_data_control SET control_value = current_max_weight::STRING
        WHERE control_name = data_control_name AND app_id = target_app_id AND control_type = algorithm_type AND control_level = 'CURRENT_MAX_WEIGHT'
          AND is_enabled = 'Y';

        UPDATE applications.tb_app_data_control SET control_value = current_load::STRING
        WHERE control_name = data_control_name AND APP_ID = target_app_id AND control_type = algorithm_type AND control_level = 'CURRENT_LOAD'
          AND is_enabled = 'Y';
    ELSE
        resource_unit := -1;
    END IF;

END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE network.load_balance_weighted_fault_avoidance(
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
    algorithm_type STRING := 'WEIGHTED_FAULT_AVOIDANCE';
    load_cache_str STRING := 'LOAD_CACHE_';
    max_cache_load INT := 1000;
    gamma FLOAT := 0.0;
    max_capacity INT := 0;
    weighted_load_map JSON[];
BEGIN
    -- Initialize HOST_IP to NULL
    host_ip := NULL;

    -- Fetch gamma value
    SELECT control_value::FLOAT INTO gamma
    FROM applications.v_app_data_control
    WHERE app_id = target_app_id AND control_name = data_control_name AND control_type = algorithm_type AND control_level = 'LOAD_ERROR_WEIGHT'
      AND is_app_enabled = 'Y' AND is_control_enabled = 'Y';

    -- Fetch max capacity
    SELECT MAX(net_load_capacity) INTO max_capacity
    FROM network.get_server_load(target_site_id)
    AS f(site_id STRING, serial_no STRING, host_ip STRING, port STRING, server_status STRING, ip_status STRING, net_load_capacity INT, session_count INT, resource_load INT, server_spec STRING, storage STRING, registration_date DATE, last_service_date DATE, location_code STRING, rack_code STRING)
    WHERE network.is_host_responsive(server_status, ip_status) = 'Y';

    -- Validate load cache
    CALL network.load_balance_validate_load_cache(target_site_id, max_cache_load);

    -- Populate weighted load map
    SELECT ARRAY(
        SELECT JSON_BUILD_OBJECT(
               't_host_ip', website_host.host_ip,
               'load_value', dist.control_value::FLOAT,
               'gamma', gamma,
               'max_capacity', max_capacity,
               'error_rate', website_host.error_rate,
               'weighted_load_value', dist.control_value::FLOAT + gamma * max_capacity::FLOAT * website_host.error_rate
        ) FROM (
            SELECT * FROM network.tb_website_host WHERE site_id = target_site_id AND network.is_host_responsive('RUNNING', status) = 'Y'
        ) website_host JOIN (
            SELECT RIGHT(control_level, LENGTH(control_level) - LENGTH(load_cache_str)) AS host_ip, control_value
            FROM applications.tb_app_data_control
            WHERE app_id = target_app_id AND control_name = data_control_name AND control_type = algorithm_type
              --AND control_level LIKE load_cache_str || '%'
              AND control_level IN (
                  SELECT load_cache_str || t_host_ip
                  FROM network.get_server_load(target_site_id)
                  AS f(site_id STRING, serial_no STRING, t_host_ip STRING, port STRING, server_status STRING, ip_status STRING, net_load_capacity INT, session_count INT, resource_load INT, server_spec STRING, storage STRING, registration_date DATE, last_service_date DATE, location_code STRING, rack_code STRING)
                  WHERE network.is_host_responsive(server_status, ip_status) = 'Y' AND net_load_capacity - resource_load > resource_size
              )
        ) dist ON website_host.host_ip = dist.host_ip
    ) INTO weighted_load_map;

    -- Log the distribution of weighted loads
    INSERT INTO applications.tb_central_system_log (
      log_id, app_id, system_name, trace_id, record_type, 
      record_value1, record_value2, record_value3, record_value4, record_value5, 
      record_message, record_note, edit_by, edit_time
    )
    SELECT experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S') || '_' || gen_random_uuid(),
           target_app_id,
           (lm->'t_host_ip')::STRING,
           COALESCE(client_thread_id, gen_random_uuid()::STRING),
           'NOTE',
           'LOAD: ' || (lm->'load_value')::STRING,
           'GAMMA: ' || (lm->'gamma')::STRING,
           'MAX_CAPACITY: ' || (lm->'max_capacity')::STRING,
           'ERROR_RATE: ' || (lm->'error_rate')::STRING,
           'WEIGHTED_LOAD_VALUE: ' || (lm->'weighted_load_value')::STRING,
           '',
           'Distribution of weighted loads of active hosts during load balancing.',
           target_app_id,
           CURRENT_TIMESTAMP
    FROM UNNEST(weighted_load_map) AS lm;

    -- Select the host with the lowest weighted load value
    SELECT (lm->'t_host_ip')::STRING INTO host_ip FROM UNNEST(weighted_load_map) AS lm
    ORDER BY (lm->'weighted_load_value')::FLOAT ASC LIMIT 1;

    -- Update the control value for the selected host
    IF host_ip IS NOT NULL THEN
        UPDATE applications.tb_app_data_control
        SET control_value = (control_value::FLOAT + resource_size::FLOAT)::STRING,
            is_enabled = 'Y',
            edit_by = target_app_id,
            edit_date = CURRENT_TIMESTAMP
        WHERE app_id = target_app_id AND control_name = data_control_name AND control_type = algorithm_type AND control_level = load_cache_str || host_ip;

        resource_unit := 1;
    ELSE
        resource_unit := -1;
    END IF;
END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE network.load_balance(
    target_site_id STRING,
    client_ip STRING,
    client_thread_id STRING,
    resource_size INT,
    OUT host_ip STRING,
    OUT resource_unit INT
)
LANGUAGE PLpgSQL AS $$
DECLARE
    algorithm STRING;
BEGIN
    host_ip := NULL;

    -- Clear out abnormal sessions
    CALL network.validate_user_sessions(target_site_id);

    -- Check if client already has a valid session on a functioning host
    SELECT h.host_ip INTO host_ip
    FROM network.tb_website_host h
    WHERE h.site_id = target_site_id
      AND network.is_host_responsive('RUNNING', h.status) = 'Y'
      AND h.host_ip IN (
          SELECT s.host_ip FROM network.tb_user_session s
          WHERE s.client_ip = client_ip AND s.thread_id = client_thread_id AND s.is_valid = 'Y'
      )
    LIMIT 1;

    IF host_ip IS NOT NULL THEN
        resource_unit := -1;
        RETURN;
    END IF;

    -- Determine load balancing algorithm
    SELECT load_balancing_algorithm INTO algorithm
    FROM network.tb_website
    WHERE site_id = target_site_id AND is_enabled = 'Y';

    -- Execute the appropriate load balancing algorithm
    IF algorithm = 'WEIGHTED_ROUND_ROBIN' THEN
        CALL network.load_balance_weighted_round_robin(target_site_id, client_ip, client_thread_id, resource_size, host_ip, resource_unit);

    ELSIF algorithm = 'LEAST_CONNECTIONS' THEN
        CALL network.load_balance_least_connections(target_site_id, client_ip, client_thread_id, resource_size, host_ip, resource_unit);

    ELSIF algorithm = 'GEOLOCATION_GLOBAL' THEN
        resource_unit := 1;

    ELSIF algorithm = 'WEIGHTED_FAULT_AVOIDANCE' THEN
        CALL network.load_balance_weighted_fault_avoidance(target_site_id, client_ip, client_thread_id, resource_size, host_ip, resource_unit);

    ELSE
        algorithm := 'NONE';
        CALL network.load_balance_none(target_site_id, client_ip, client_thread_id, resource_size, host_ip, resource_unit);
    END IF;

    -- Handle case where no host is selected
    IF host_ip IS NULL THEN
        resource_unit := -1;
    END IF;

    -- Debugging output (optional)
    RAISE NOTICE 'Algorithm used: %', algorithm;
END;
$$;
-- +goose StatementEnd



-- +goose Down
DROP PROCEDURE IF EXISTS network.load_balance;
DROP PROCEDURE IF EXISTS network.load_balance_weighted_fault_avoidance;
DROP PROCEDURE IF EXISTS network.load_balance_weighted_round_robin;
--DROP TYPE IF EXISTS network.server_load;
--DROP TYPE IF EXISTS applications.data_control_kv;
DROP PROCEDURE IF EXISTS network.load_balance_least_connections;
DROP PROCEDURE IF EXISTS network.load_balance_none;
DROP PROCEDURE IF EXISTS network.load_balance_reset;
DROP PROCEDURE IF EXISTS network.load_balance_validate_load_cache;
