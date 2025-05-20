-- +goose Up
CREATE SCHEMA communications;

CREATE TABLE communications.tb_email_header (
	email_id STRING(100) NOT NULL PRIMARY KEY,
	uploaded_by STRING(100) NOT NULL,
	uploaded_time TIMESTAMP DEFAULT current_timestamp NOT NULL,
	scheduled_time TIMESTAMP DEFAULT current_timestamp NOT NULL,
	status STRING(20) NOT NULL,
	note STRING(250) NOT NULL,
	edit_by STRING(100) NOT NULL,
	edit_time TIMESTAMP DEFAULT current_timestamp NOT NULL,
	INDEX (status, scheduled_time DESC)
);

CREATE TABLE communications.tb_message_backlog_spec (
	spec_id STRING(100) NOT NULL PRIMARY KEY DEFAULT experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S') || '_' || gen_random_uuid(),
	userid STRING(100) NOT NULL,
	message_type STRING(20) NOT NULL,
	template_id STRING(100) NULL,
	schedule STRING(20) NOT NULL, -- CRON expression
	audit_schedule STRING(20) NOT NULL,
	backlog_window FLOAT NOT NULL, -- allowed window to complete the backlog
	is_in_audit CHAR NOT NULL CHECK (is_in_audit IN ('Y', 'N')),
	is_enabled CHAR NOT NULL CHECK (is_enabled IN ('Y', 'N')),
	edit_by STRING(100) NOT NULL,
	edit_time TIMESTAMP DEFAULT current_timestamp NOT NULL,
	CONSTRAINT fk_app_user FOREIGN KEY (userid) REFERENCES auth.tb_app_user (userid)
);

CREATE TABLE communications.tb_message_backlog (
	backlog_id STRING(100) NOT NULL PRIMARY KEY DEFAULT experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S') || '_' || gen_random_uuid(),
	spec_id STRING(100) NOT NULL,
	due_time TIMESTAMP NOT NULL,
	status STRING(20) NOT NULL,
	note STRING(250) NOT NULL,
	edit_by STRING(100) NOT NULL,
	edit_time TIMESTAMP DEFAULT current_timestamp NOT NULL,
	CONSTRAINT fk_backlog_spec FOREIGN KEY (spec_id) REFERENCES communications.tb_message_backlog_spec(spec_id)
);




-- +goose StatementBegin
CREATE PROCEDURE communications.update_message_backlog_statuses(
    target_message_type STRING,
    target_edit_by STRING
)
LANGUAGE PLpgSQL AS $$
BEGIN
    -- Update backlogs status of all message types if not specified
    IF target_message_type IS NULL THEN
		UPDATE communications.tb_message_backlog
		SET status = 'PASTDUE', edit_by = target_edit_by, edit_time = CURRENT_TIMESTAMP
		WHERE status IN ('AWAITING') AND due_time < CURRENT_TIMESTAMP;

		RETURN;
	END IF;
	
    -- Update backlogs status of the specified message type:
	UPDATE communications.tb_message_backlog
	SET status = 'PASTDUE', edit_by = target_edit_by, edit_time = CURRENT_TIMESTAMP
	WHERE status IN ('AWAITING') AND due_time < CURRENT_TIMESTAMP AND spec_id IN (
		SELECT S.spec_id FROM communications.tb_message_backlog_spec S
		WHERE S.message_type = target_message_type
	);
END;
$$;
-- +goose StatementEnd



-- +goose StatementBegin
CREATE PROCEDURE communications.resolve_message_backlog(
	target_backlog_id STRING,
    target_message_id STRING,
    target_edit_by STRING
)
LANGUAGE PLpgSQL AS $$
DECLARE
    message_userid STRING := NULL;
	backlog_userid STRING := NULL;
	backlog_message_type STRING := NULL;
BEGIN
	-- Query backlog spec user and message type
	SELECT userid, message_type INTO backlog_userid, backlog_message_type
	FROM communications.tb_message_backlog_spec
	WHERE spec_id IN (
		SELECT B.spec_id FROM communications.tb_message_backlog B 
		WHERE B.backlog_id = target_backlog_id
	);
	
	-- Validate message user and spec user
	IF backlog_message_type = 'EMAIL' THEN
		SELECT uploaded_by INTO message_userid 
		FROM communications.tb_email_header
		WHERE email_id = target_message_id;
	ELSE 
		RAISE EXCEPTION 'Backlog message type not found!';
	END IF;

	IF message_userid IS NULL OR message_userid <> backlog_userid THEN
		RAISE EXCEPTION 'Unauthorized backlog resolve operation!';
	END IF;

    -- Update backlog status as 'RESOLVED'
	UPDATE communications.tb_message_backlog
	SET status = 'RESOLVED', note = backlog_message_type || ' ID: ' || target_message_id, edit_by = target_edit_by, edit_time = CURRENT_TIMESTAMP
	WHERE backlog_id = target_backlog_id;
	
END;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE FUNCTION communications.get_message_backlog_by_user(
    target_userid STRING,
	target_type STRING, -- optional
	target_status STRING -- optional
)
RETURNS SETOF communications.tb_message_backlog LANGUAGE SQL AS $$
	SELECT * FROM communications.tb_message_backlog B WHERE B.spec_id IN (
		SELECT S.spec_id FROM communications.tb_message_backlog_spec S
		WHERE S.userid = target_userid 
		AND (target_type IS NULL OR S.message_type = target_type)
	) AND (target_status IS NULL OR B.status = target_status);
$$;
-- +goose StatementEnd



-- +goose Down
DROP FUNCTION IF EXISTS communications.get_message_backlog_by_user;

DROP PROCEDURE IF EXISTS communications.resolve_message_backlog;
DROP PROCEDURE IF EXISTS communications.update_message_backlog_statuses;

DROP TABLE IF EXISTS communications.tb_message_backlog;
DROP TABLE IF EXISTS communications.tb_message_backlog_spec;
DROP TABLE IF EXISTS communications.tb_email_header;

DROP SCHEMA IF EXISTS communications;

