-- +goose Up
CREATE SCHEMA network;

CREATE TABLE network.tb_website (
    site_id STRING(100) NOT NULL,
    app_id STRING(100) NOT NULL,
    domain_name STRING NOT NULL,
    site_name STRING(100) NOT NULL,
    load_balancing_algorithm STRING(50) NOT NULL,
    theme_color STRING(20) NOT NULL,
    is_enabled CHAR(1) NOT NULL CHECK (is_enabled IN ('N', 'Y')),
    owned_by STRING(100) NOT NULL,
    edit_by STRING(100) NOT NULL,
    edit_time TIMESTAMP NOT NULL,
    CONSTRAINT pk_tb_website PRIMARY KEY (site_id),
    CONSTRAINT fk_tb_website_app_id FOREIGN KEY (app_id) REFERENCES applications.tb_app (app_id)
);

CREATE TABLE network.tb_website_host (
    host_ip STRING(1000) NOT NULL,
    port STRING(10) NOT NULL,
    site_id STRING(100),
    serial_no STRING(50),
    status STRING(20) CHECK (status IN ('ERROR', 'DISABLED', 'UNRESPONSIVE', 'NORMAL')),
    edit_by STRING(100) NOT NULL,
    edit_time TIMESTAMP NOT NULL,
    error_measurement_algorithm STRING(100) DEFAULT '' NOT NULL,
    error_rate FLOAT DEFAULT 0.0 NOT NULL,
    measured_time TIMESTAMP DEFAULT current_timestamp() NOT NULL,
    CONSTRAINT pk_website_host PRIMARY KEY (host_ip, port),
    CONSTRAINT fk_website_host_serial_no FOREIGN KEY (serial_no) REFERENCES products.tb_server (serial_no),
    CONSTRAINT fk_website_host_site_id FOREIGN KEY (site_id) REFERENCES network.tb_website (site_id)
);

CREATE TABLE network.tb_host_status_log (
    log_id STRING(150) NOT NULL,
    host_ip STRING(1000) NOT NULL,
    host_status STRING(20) NOT NULL,
    trace_id STRING(100),
    record_type STRING(50) CHECK (record_type IN ('NOTE', 'WARNING', 'ERROR', 'GOOD')),
    record_message STRING NOT NULL,
    error_rate FLOAT NOT NULL,
    edit_by STRING(100) NOT NULL,
    edit_time TIMESTAMP NOT NULL,
    latency FLOAT DEFAULT 0 NOT NULL,
    CONSTRAINT pk_host_status_log PRIMARY KEY (log_id)
);
CREATE INDEX host_status_log_time_idx ON network.tb_host_status_log (host_ip ASC, edit_by DESC);

CREATE TABLE network.tb_user_session (
    session_id STRING(100) DEFAULT experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S') || '_' || gen_random_uuid() NOT NULL,
    client_ip STRING(1000) NOT NULL,
    thread_id STRING(100) NOT NULL,
    host_ip STRING(1000),
    resource_unit INT NOT NULL,
    client_location STRING(150) NOT NULL,
    requested_time TIMESTAMP NOT NULL,
    resource_size INT NOT NULL,
    edit_by STRING(100) NOT NULL,
    edit_time TIMESTAMP NOT NULL,
    is_valid CHAR CHECK (is_valid IN ('N', 'Y')),
    CONSTRAINT pk_user_session PRIMARY KEY (session_id),
    CONSTRAINT uq_client_thread_host UNIQUE (client_ip, thread_id, host_ip)
);

CREATE TABLE network.tb_user_session_item (
    session_id STRING(100) NOT NULL,
    item_name STRING(250) NOT NULL,
    item_description STRING NOT NULL,
    item_size INT NOT NULL,
    item_route STRING(500) NOT NULL,
    item_policy STRING NOT NULL,
    expiration_time TIMESTAMP,
    edit_by STRING(100) NOT NULL,
    edit_time TIMESTAMP NOT NULL,
    CONSTRAINT pk_user_session_item PRIMARY KEY (session_id, item_name),
    CONSTRAINT fk_user_session FOREIGN KEY (session_id) REFERENCES network.tb_user_session (session_id)
);

CREATE TABLE network.tb_user_session_history_log (
    session_id STRING(100) NOT NULL,
    client_ip STRING(1000) NOT NULL,
    thread_id STRING(100) NOT NULL,
    host_ip STRING(1000) NOT NULL,
    resource_unit INT NOT NULL,
    client_location STRING(150) NOT NULL,
    requested_time TIMESTAMP NOT NULL,
    resource_size INT NOT NULL,
    edit_by STRING(100) NOT NULL,
    connected_time TIMESTAMP NOT NULL,
    disconnected_time TIMESTAMP NOT NULL,
    CONSTRAINT pk_user_session_history_log PRIMARY KEY (session_id)
);

CREATE TABLE network.tb_user_session_item_history_log (
    session_id STRING(100) NOT NULL,
    item_name STRING(250) NOT NULL,
    item_description STRING NOT NULL,
    item_size INT NOT NULL,
    item_route STRING(500) NOT NULL,
    item_policy STRING NOT NULL,
    expiration_time TIMESTAMP NULL,
    deleted_by STRING(100) NOT NULL,
    deleted_time TIMESTAMP NOT NULL
);



CREATE TYPE network.rec_db_host_latency_statistics AS (
	end_time TIMESTAMP,
	min_latency FLOAT,
	avg_latency FLOAT,
	max_latency FLOAT
);

-- +goose StatementBegin
CREATE FUNCTION network.get_db_host_latency_statistics(time_offset_hours INT, time_interval_minutes INT, target_host_ip STRING)
RETURNS SETOF network.rec_db_host_latency_statistics LANGUAGE SQL AS $$
    SELECT time_slot.end_time, MIN(status_log.latency) AS min_latency, AVG(status_log.latency) AS avg_latency, MAX(status_log.latency) AS max_latency
    FROM (
        -- query host status logs within the past time_offset_hours hours
        SELECT * FROM network.tb_host_status_log
        WHERE host_ip = target_host_ip AND edit_time >= CURRENT_TIMESTAMP - (time_offset_hours::STRING || ' HOURS')::INTERVAL
    ) status_log INNER JOIN (
        -- select all intervals in minutes
        SELECT log_time::TIMESTAMP AS start_time, (log_time + (time_interval_minutes::STRING || ' MINUTES')::INTERVAL)::TIMESTAMP AS end_time FROM (
            -- select all time check points by minute interval
            SELECT CURRENT_TIMESTAMP - ((offset_index.minute_index * time_interval_minutes)::STRING || ' MINUTES')::INTERVAL AS log_time
            FROM (SELECT generate_series(1, (time_offset_hours * 60 / time_interval_minutes)::INT) AS minute_index) offset_index
        ) list_interval
    ) time_slot ON status_log.EDIT_TIME BETWEEN time_slot.start_time AND time_slot.end_time
    GROUP BY time_slot.end_time;
$$;
-- +goose StatementEnd



CREATE TYPE network.rec_server_details AS (
	site_id STRING(100),
        serial_no STRING(50),
        host_ip STRING(1000),
        port STRING(10),
        server_status STRING(20),
        ip_status STRING(20),
        net_load_capacity INT,
        server_spec STRING(300),
        storage STRING(100),
        registration_date DATE,
        last_service_date DATE,
        location_code STRING(20),
        rack_code STRING(50)
);


-- +goose StatementBegin
CREATE FUNCTION network.get_server_details(target_site_id STRING)
RETURNS SETOF network.rec_server_details LANGUAGE SQL AS $$
    SELECT
        h.site_id,
        s.serial_no,
        h.host_ip,
        h.port,
        s.status AS server_status,
        h.status AS ip_status,
        s.net_load_capacity,
        s.server_spec,
        s.storage,
        s.registration_date,
        s.last_service_date,
        s.location_code,
        s.rack_code
    FROM products.tb_server s
    INNER JOIN (SELECT * FROM network.tb_website_host host WHERE host.site_id = target_site_id) h
    ON s.serial_no = h.serial_no
    WHERE s.status <> 'REMOVED';
$$;
-- +goose StatementEnd


CREATE TYPE network.rec_server_load AS (
	site_id STRING(100),
        serial_no STRING(50),
        host_ip STRING(1000),
        port STRING(10),
        server_status STRING(20),
        ip_status STRING(20),
        net_load_capacity INT,
        session_count INT,
        resource_load INT,
        server_spec STRING(300),
        storage STRING(100),
        registration_date DATE,
        last_service_date DATE,
        location_code STRING(20),
        rack_code STRING(50)
);

-- +goose StatementBegin
CREATE FUNCTION network.get_server_load(target_site_id STRING)
RETURNS SETOF network.rec_server_load LANGUAGE SQL AS $$
    SELECT
        ser.site_id,
        ser.serial_no,
        ser.host_ip,
        ser.port,
        ser.server_status,
        ser.ip_status,
        ser.net_load_capacity,
        COALESCE(dist.session_count, 0) AS session_count,
        COALESCE(dist.resource_load, 0) AS resource_load,
        ser.server_spec,
        ser.storage,
        ser.registration_date,
        ser.last_service_date,
        ser.location_code,
        ser.rack_code
    FROM (
        SELECT s.serial_no, s.net_load_capacity, s.status AS server_status, h.host_ip, h.port, h.site_id,
               h.status AS ip_status, s.server_spec, s.storage, s.registration_date, s.last_service_date,
               s.location_code, s.rack_code
        FROM products.tb_server s
        INNER JOIN (SELECT * FROM network.tb_website_host WHERE site_id = target_site_id) h ON s.serial_no = h.serial_no
    ) AS ser
    LEFT JOIN (
        SELECT us.host_ip, COUNT(us.session_id) AS session_count, SUM(us.resource_size)::INT AS resource_load
        FROM network.tb_user_session us
        WHERE us.host_ip IN (SELECT host_ip FROM network.tb_website_host WHERE site_id = target_site_id)
        GROUP BY us.host_ip
    ) AS dist
    ON ser.host_ip = dist.host_ip;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE FUNCTION network.is_host_responsive(server_status STRING, ip_status STRING)
RETURNS CHAR(1) LANGUAGE PLpgSQL AS $$
DECLARE
    yes CHAR(1) := 'Y';
    no CHAR(1) := 'N';
BEGIN
    -- Check if server_status or ip_status is NULL
    IF server_status IS NULL THEN RETURN no; END IF;
    IF ip_status IS NULL THEN RETURN no; END IF;

    -- Check if server_status is not 'RUNNING'
    IF server_status NOT IN ('RUNNING') THEN RETURN no; END IF;

    -- Check if ip_status is not in ('NORMAL', 'ERROR')
    IF ip_status NOT IN ('NORMAL', 'ERROR') THEN RETURN no; END IF;

    -- If all checks pass, return 'Y'
    RETURN yes;
END;
$$;
-- +goose StatementEnd





-- +goose StatementBegin
CREATE PROCEDURE network.invalidate_user_sessions(
    target_session_id STRING DEFAULT NULL,
    target_client_ip STRING DEFAULT NULL,
    target_thread_id STRING DEFAULT NULL,
    target_host_ip STRING DEFAULT NULL
)
LANGUAGE PLpgSQL AS $$
DECLARE invalidated_sessions STRING[];
BEGIN
    -- Step 1: Invalidate sessions
    UPDATE network.tb_user_session SET is_valid = 'N'
    WHERE (session_id = target_session_id OR target_session_id IS NULL)
      AND (client_ip = target_client_ip OR target_client_ip IS NULL)
      AND (thread_id = target_thread_id OR target_thread_id IS NULL)
      AND (host_ip = target_host_ip OR target_host_ip IS NULL);

    -- Step 2: Collect invalidated sessions
    SELECT ARRAY_AGG(session_id) INTO invalidated_sessions
    FROM network.tb_user_session
    WHERE is_valid = 'N';

    -- Step 3: Log invalidated sessions to history log
    INSERT INTO network.tb_user_session_history_log
    SELECT session_id, client_ip, thread_id, host_ip, resource_unit,
           client_location, requested_time, resource_size, edit_by,
           edit_time, current_timestamp AS disconnected_time
    FROM network.tb_user_session
    WHERE session_id = ANY(invalidated_sessions);

    -- Step 4: Log invalidated session items to history log
    INSERT INTO network.tb_user_session_item_history_log
    SELECT * FROM network.tb_user_session_item
    WHERE session_id = ANY(invalidated_sessions);

    -- Step 5: Delete session items for invalidated sessions
    DELETE FROM network.tb_user_session_item
    WHERE session_id = ANY(invalidated_sessions);

    -- Step 6: Delete invalidated sessions
    DELETE FROM network.tb_user_session
    WHERE session_id = ANY(invalidated_sessions);
END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE network.validate_user_sessions(target_site_id STRING)
LANGUAGE PLpgSQL AS $$
DECLARE problem_host_ips STRING[];
BEGIN
    -- Determine problem hosts
    SELECT ARRAY_AGG(host_ip) INTO problem_host_ips
    FROM network.tb_website_host WHERE serial_no IN (
        SELECT h.serial_no
        FROM network.tb_website_host h
        WHERE h.site_id = target_site_id AND network.is_host_responsive('RUNNING', h.status) = 'N'
        UNION
        SELECT s.serial_no
        FROM products.tb_server s
	WHERE s.serial_no IN (SELECT hsub.serial_no FROM network.tb_website_host hsub WHERE hsub.site_id = target_site_id)
              AND network.is_host_responsive(s.status, 'NORMAL') = 'N'
    );

    -- Invalidate sessions for problem hosts
    UPDATE network.tb_user_session SET is_valid = 'N'
    WHERE host_ip = ANY(problem_host_ips);

    -- Clear session data and write into session logs (Dummy example logic, as specifics are unclear)
    CALL network.invalidate_user_sessions('XXXXXXX', 'X.X.X.X', 'XXXXXXXX', 'X.X.X.X');
END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE network.insert_host_status_log(
    target_host_ip STRING,
    target_host_status STRING,
    target_trace_id STRING,
    input_message STRING,
    target_edit_by STRING,
    target_latency FLOAT8 DEFAULT 0
)
LANGUAGE PLpgSQL AS $$
DECLARE
    target_app_id STRING := 'CloudSharpSystemsWeb';
    prev_error_rate FLOAT8;			-- temporary memory: previous error rate
    prev_record_time TIMESTAMP;			-- temporary memory: previous record time
    cutoff_days FLOAT8 := 30.0;			-- only considers records within the last cutoff_days days
    estimation_date TIMESTAMP := CURRENT_TIMESTAMP;				 -- set current time
    cutoff_date TIMESTAMP := estimation_date - (INTERVAL '1 day' * cutoff_days); -- date of the cutoff threshold
    cutoff_seconds FLOAT8 := cutoff_days * 24 * 60 * 60;			 -- cutoff_days in seconds
    age FLOAT8;					-- gap between the latest measure times in seconds
    scale FLOAT8;				-- weight to assign to beta0 based on age (the older, the less important)
    alpha FLOAT8;				-- weight to assign to new error rate
    beta_0 FLOAT8;				-- weight to assign to previous error rate (in uniform intervals)
    beta FLOAT8;				-- final weight to assign to previous error rate (beta_0 * scale)
    new_error_rate FLOAT8;
BEGIN
    -- 1. Query most recent error rate and record time, disregard records older than 30 days
    SELECT error_rate, measured_time INTO prev_error_rate, prev_record_time
    FROM network.tb_website_host
    WHERE host_ip = target_host_ip AND status <> 'DISABLED' AND measured_time > cutoff_date
    ORDER BY measured_time DESC LIMIT 1;

    prev_error_rate := COALESCE(prev_error_rate, 0);
    prev_record_time := COALESCE(prev_record_time, cutoff_date);

    -- 2. Calculate the new error rate based on host status
    age := EXTRACT(EPOCH FROM (estimation_date - prev_record_time));
    scale := SQRT((cutoff_seconds - age) / cutoff_seconds);

    SELECT control_value::FLOAT8 INTO alpha
    FROM applications.v_app_data_control
    WHERE app_id = app_id AND control_name = 'SYSTEM_HEALTH_ANALYZER' AND control_type = 'ERROR_ANALYSIS_CONFIG' AND control_level = 'EWMA_ERROR_WEIGHT'
          AND is_app_enabled = 'Y'
          AND is_control_enabled = 'Y'
    LIMIT 1;

    beta_0 := 1 - alpha;
    beta := beta_0 * scale;
    new_error_rate := beta * prev_error_rate + (1 - beta) * (CASE target_host_status WHEN 'NORMAL' THEN 0.0 ELSE 1.0 END)::FLOAT8;
    IF new_error_rate < 0.0001 THEN
        new_error_rate := 0; -- Apply lower bound
    END IF;

    -- 3. Insert new record into the host status log table
    INSERT INTO network.tb_host_status_log (
        log_id,
        host_ip,
        host_status,
        trace_id,
        record_type,
        record_message,
        error_rate,
        edit_by,
        edit_time,
        latency
    )
    VALUES (
	experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S') || '_' || gen_random_uuid(),
        target_host_ip,
        target_host_status,
        target_trace_id,
        CASE target_host_status WHEN 'NORMAL' THEN 'GOOD' ELSE 'ERROR' END,
        input_message,
        new_error_rate,
        target_edit_by,
        estimation_date,
        target_latency
    );

    -- 4. Update error rate record in the website host table
    UPDATE network.tb_website_host
    SET error_measurement_algorithm = 'EWMA',
        error_rate = new_error_rate,
        measured_time = estimation_date,
        edit_by = target_edit_by,
        edit_time = CURRENT_TIMESTAMP
    WHERE host_ip = target_host_ip;
END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE network.update_host_status(
    target_host_ip STRING,
    target_port STRING,
    target_status STRING,
    target_edit_by STRING,
    target_trace_id STRING DEFAULT NULL,
    input_message STRING DEFAULT '',
    target_latency FLOAT DEFAULT 0
)
LANGUAGE PLpgSQL AS $$
DECLARE target_site_id STRING;
BEGIN
    -- Update the status of the host
    UPDATE network.tb_website_host SET status = target_status, edit_by = target_edit_by, edit_time = CURRENT_TIMESTAMP
    WHERE host_ip = target_host_ip AND port = target_port;

    -- Retrieve the SITE_ID
    SELECT site_id INTO target_site_id FROM network.tb_website_host
    WHERE host_ip = target_host_ip AND port = target_port;

    -- Insert a host status log
    CALL network.insert_host_status_log(target_host_ip, target_status, target_trace_id, input_message, target_edit_by, target_latency);

    -- If SITE_ID is not null, validate user sessions
    IF target_site_id IS NOT NULL THEN CALL network.validate_user_sessions(target_site_id); END IF;
END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE network.update_host_ip_by_sn(sn STRING, new_ip STRING)
LANGUAGE SQL AS $$
    UPDATE network.tb_website_host SET host_ip = new_ip, edit_by = 'AutoIPRegistrationTask', edit_time = CURRENT_TIMESTAMP
    WHERE UPPER(serial_no) = UPPER(sn);
$$;
-- +goose StatementEnd








-- +goose Down
DROP PROCEDURE IF EXISTS network.update_host_ip_by_sn;
DROP PROCEDURE IF EXISTS network.update_host_status;
DROP PROCEDURE IF EXISTS network.insert_host_status_log;
DROP PROCEDURE IF EXISTS network.validate_user_sessions;
DROP PROCEDURE IF EXISTS network.invalidate_user_sessions;

DROP FUNCTION IF EXISTS network.is_host_responsive;
DROP FUNCTION IF EXISTS network.get_server_load;
DROP FUNCTION IF EXISTS network.get_server_details;
DROP FUNCTION IF EXISTS network.get_db_host_latency_statistics;
DROP TYPE IF EXISTS network.rec_server_load;
DROP TYPE IF EXISTS network.rec_server_details;
DROP TYPE IF EXISTS network.rec_db_host_latency_statistics;

DROP TABLE IF EXISTS network.tb_user_session_item_history_log;
DROP TABLE IF EXISTS network.tb_user_session_history_log;
DROP TABLE IF EXISTS network.tb_user_session_item;
DROP TABLE IF EXISTS network.tb_user_session;
DROP TABLE IF EXISTS network.tb_host_status_log;
DROP TABLE IF EXISTS network.tb_website_host;
DROP TABLE IF EXISTS network.tb_website;

DROP SCHEMA IF EXISTS network;

