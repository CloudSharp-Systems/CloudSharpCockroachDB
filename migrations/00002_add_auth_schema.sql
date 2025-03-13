-- +goose Up
CREATE SCHEMA auth;

CREATE TABLE auth.tb_app_user (
    userid           STRING(100) NOT NULL DEFAULT experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S') || '_' || gen_random_uuid(),
    password_salt    STRING(50) NOT NULL,
    password_hash    STRING(50) NOT NULL,
    first_name       STRING(100) NOT NULL,
    last_name        STRING(100) NOT NULL,
    name_alias       STRING(100) NOT NULL,
    phone_number     STRING(50) NOT NULL,
    profile_picture  STRING(500) NOT NULL,
    notes            STRING(500) NOT NULL,
    is_enabled       CHAR(1) CHECK (is_enabled IN ('N', 'Y')) NOT NULL,
    last_login_time  TIMESTAMP NULL,
    created_time     TIMESTAMP DEFAULT current_timestamp NOT NULL,
    edit_by          STRING(100) NOT NULL,
    edit_time        TIMESTAMP DEFAULT current_timestamp NOT NULL,
    PRIMARY KEY (userid)
);

CREATE TABLE auth.tb_app_user_identity (
    identity_provider STRING(100) NOT NULL,
    username          STRING(200) NOT NULL,
    userid            STRING(100) NOT NULL,
    username_alias    STRING(200) NOT NULL,
    language_code     STRING(10) NOT NULL,
    is_enabled        CHAR(1) CHECK (is_enabled IN ('N', 'Y')) NOT NULL,
    edit_by           STRING(100) NOT NULL,
    edit_time         TIMESTAMP DEFAULT current_timestamp NOT NULL,
    PRIMARY KEY (identity_provider, username),
    CONSTRAINT fk_userid FOREIGN KEY (userid) REFERENCES auth.tb_app_user (userid),
    CONSTRAINT uq_identity_alias UNIQUE (identity_provider, username_alias)
);

CREATE TABLE auth.tb_app_user_identity_delete_log (
    identity_provider STRING(100) NOT NULL,
    username          STRING(200) NOT NULL,
    userid            STRING(100) NOT NULL,
    username_alias    STRING(200) NOT NULL,
    language_code     STRING(10) NOT NULL,
    is_enabled        CHAR(1) CHECK (is_enabled IN ('N', 'Y')) NOT NULL,
    deleted_by        STRING(100) NOT NULL,
    deleted_time      TIMESTAMP DEFAULT current_timestamp NOT NULL
);

CREATE TABLE auth.tb_app_team (
    team_id          STRING(100) NOT NULL DEFAULT experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S') || '_' || gen_random_uuid(),
    app_id           STRING(100) NOT NULL,
    team_name        STRING(50) NOT NULL,
    team_description STRING NOT NULL,
    profile_picture  STRING(500) NOT NULL,
    primary_contact  STRING(200) NOT NULL,
    is_enabled       CHAR(1) CHECK (is_enabled IN ('N', 'Y')) NOT NULL,
    owned_by         STRING(100) NOT NULL,
    edit_by          STRING(100) NOT NULL,
    edit_time        TIMESTAMP DEFAULT current_timestamp NOT NULL,
    PRIMARY KEY (team_id),
    CONSTRAINT fk_app FOREIGN KEY (app_id) REFERENCES applications.tb_app (app_id),
    CONSTRAINT uq_tb_app_team UNIQUE (app_id, team_name)
);

CREATE TABLE auth.tb_app_user_team (
    userid      STRING(100) NOT NULL,
    team_id     STRING(100) NOT NULL,
    is_enabled  CHAR(1) CHECK (is_enabled IN ('N', 'Y')) NOT NULL,
    edit_by     STRING(100) NOT NULL,
    edit_time   TIMESTAMP DEFAULT current_timestamp NOT NULL,
    PRIMARY KEY (userid, team_id),
    CONSTRAINT fk_team_id FOREIGN KEY (team_id) REFERENCES auth.tb_app_team (team_id),
    CONSTRAINT fk_userid FOREIGN KEY (userid) REFERENCES auth.tb_app_user (userid)
);







CREATE TYPE auth.rec_app_identity_user_profile_header AS (
	first_name STRING(100),
	last_name STRING(100),
	name_alias STRING(200),
	phone_number STRING(50),
	profile_picture STRING(500),
	notes STRING(500),
	identity_provider STRING(100),
	username_alias STRING(200),
	language_code STRING(10)
);


-- +goose StatementBegin
CREATE FUNCTION auth.get_app_identity_user_profile_header(
    target_identity_provider STRING(100),
    target_userid STRING(100)
)
RETURNS SETOF auth.rec_app_identity_user_profile_header LANGUAGE SQL AS $$
    SELECT
        u.first_name,
        u.last_name,
        u.name_alias,
        u.phone_number,
        u.profile_picture,
        u.notes,
        i.identity_provider,
        i.username_alias,
        i.language_code
    FROM auth.tb_app_user u
    INNER JOIN (
	SELECT *
        FROM auth.tb_app_user_identity
        WHERE identity_provider = target_identity_provider AND userid = target_userid AND is_enabled = 'Y'
    ) i ON u.userid = i.userid;
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE FUNCTION auth.get_app_identity_user_profile_headers_by_provider(
    target_identity_provider STRING(100),
    target_team_id STRING(100)
) RETURNS SETOF auth.rec_app_identity_user_profile_header LANGUAGE SQL AS $$
    SELECT u.first_name, u.last_name, u.name_alias, u.phone_number, u.profile_picture, u.notes, i.identity_provider, i.username_alias, i.language_code
    FROM (
        SELECT ut.* FROM auth.tb_app_user_team ut WHERE ut.team_id = target_team_id AND ut.is_enabled = 'Y'
    ) team_user -- query users in the target team
    INNER JOIN auth.tb_app_user_identity i ON team_user.userid = i.userid AND i.is_enabled = 'Y'
    INNER JOIN auth.tb_app_user u ON u.userid = i.userid AND u.is_enabled = 'Y'
    -- get user profiles including identity info
    WHERE identity_provider = target_identity_provider
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE FUNCTION auth.get_app_identity_user_profile_headers_by_team(
    target_identity_provider STRING(100),
    target_team_id STRING(100)
)
RETURNS SETOF auth.rec_app_identity_user_profile_header LANGUAGE SQL AS $$

    -- 1. query profile from the target provider
    SELECT * FROM auth.get_app_identity_user_profile_headers_by_provider(target_identity_provider, target_team_id)
    -- AS head_by_p(first_name STRING, last_name STRING, name_alias STRING, phone_number STRING, profile_picture STRING, notes STRING, identity_provider STRING, username_alias STRING, language_code STRING)

    UNION ALL

    -- 2. query profile from the CloudSharp provider
    SELECT * FROM auth.get_app_identity_user_profile_headers_by_provider(
    	(SELECT control_value FROM applications.tb_app_data_control
        WHERE app_id = 'CloudSharpSystemsWeb' AND control_name = 'IDENTITY_PROVIDER' AND control_type = 'PROVIDER_NAME' AND is_enabled = 'Y' LIMIT 1),
    target_team_id) head_by_cs
    -- AS head_by_cs(first_name STRING, last_name STRING, name_alias STRING, phone_number STRING, profile_picture STRING, notes STRING, identity_provider STRING, username_alias STRING, language_code STRING)
    -- exclude profiles already collected in (1)
    WHERE head_by_cs.username_alias NOT IN (
        SELECT head_by_psub.username_alias FROM auth.get_app_identity_user_profile_headers_by_provider(target_identity_provider, target_team_id)
	head_by_psub
        --AS head_by_psub(first_name STRING, last_name STRING, name_alias STRING, phone_number STRING, profile_picture STRING, notes STRING, identity_provider STRING, username_alias STRING, language_code STRING)
    );
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE FUNCTION auth.get_teams_by_user(
    target_app_id STRING(100),
    target_userid STRING(100),
    with_default_account CHAR(1)
)
RETURNS SETOF auth.tb_app_team LANGUAGE SQL AS $$
    SELECT * FROM auth.tb_app_team
    WHERE app_id = target_app_id AND team_id IN (
        SELECT team_id FROM auth.tb_app_user_team
        WHERE userid = target_userid AND is_enabled = 'Y'
    ) AND is_enabled = 'Y'
    UNION
    SELECT * FROM auth.tb_app_team
    WHERE app_id = target_app_id AND team_name = 'My Notes' AND is_enabled = 'Y' AND with_default_account = 'Y';
$$;
-- +goose StatementEnd


-- +goose StatementBegin
CREATE PROCEDURE auth.add_app_user(
    app_id STRING,
    password_salt STRING DEFAULT 'NONE',
    password_hash STRING DEFAULT '',
    first_name STRING DEFAULT '',
    last_name STRING DEFAULT '',
    name_alias STRING DEFAULT '',
    phone_number STRING DEFAULT '',
    profile_picture STRING DEFAULT '',
    identity_provider STRING DEFAULT '',
    username STRING DEFAULT '',
    username_alias STRING DEFAULT '',
    language_code STRING DEFAULT 'en',
    is_enabled CHAR(1) DEFAULT 'Y',
    edit_by STRING DEFAULT ''
)
LANGUAGE PLpgSQL AS $$
DECLARE
    uid STRING(100) := experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S')::STRING || '_' || gen_random_uuid()::STRING;
    cloud_sharp_provider STRING(100);
    log_id STRING(100) := experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d%H%M%S')::STRING || '_' || gen_random_uuid()::STRING;
BEGIN
    -- Insert into TB_APP_USER
    INSERT INTO auth.tb_app_user (
        userid, password_salt, password_hash, first_name, last_name, name_alias,
        phone_number, profile_picture, notes, is_enabled, last_login_time,
        created_time, edit_by, edit_time
    )
    VALUES (
        uid,
        password_salt,
        password_hash,
        first_name,
        last_name,
        CASE WHEN name_alias IS NULL OR name_alias = '' THEN first_name || ' ' || last_name ELSE name_alias END,
        phone_number,
        profile_picture,
        'New user, created on ' || experimental_strftime(CURRENT_TIMESTAMP, '%Y%m%d') || '.',
        is_enabled,
        NULL,
        CURRENT_TIMESTAMP,
        edit_by,
        CURRENT_TIMESTAMP
    );

    -- Get CloudSharpProvider value
    SELECT control_value INTO cloud_sharp_provider
    FROM applications.tb_app_data_control
    WHERE app_id = 'CloudSharpSystemsWeb' AND control_name = 'IDENTITY_PROVIDER' AND control_type = 'PROVIDER_NAME' AND is_enabled = 'Y'
    LIMIT 1;

    IF cloud_sharp_provider IS NULL OR cloud_sharp_provider = '' THEN
        RAISE EXCEPTION 'CloudSharp Identity Provider not found in DB! Check APPLICATIONS.TB_APP_DATA_CONTROL for Identity Provider name config.';
    END IF;

    -- Insert into TB_APP_USER_IDENTITY for CloudSharpProvider
    INSERT INTO auth.tb_app_user_identity (
        identity_provider, username, userid, username_alias, language_code, is_enabled, edit_by, edit_time
    )
    VALUES (
        cloud_sharp_provider,
        username,
        uid,
        CASE WHEN username_alias IS NULL OR username_alias = '' THEN username ELSE username_alias END,
        language_code,
        is_enabled,
        edit_by,
        CURRENT_TIMESTAMP
    );

    -- Insert into TB_APP_USER_IDENTITY for additional provider
    IF identity_provider != cloud_sharp_provider THEN
        INSERT INTO auth.tb_app_user_identity (
            identity_provider, username, userid, username_alias, language_code, is_enabled, edit_by, edit_time
        )
        VALUES (
            identity_provider,
            username,
            uid,
            CASE WHEN username_alias IS NULL OR username_alias = '' THEN username ELSE username_alias END,
            language_code,
            is_enabled,
            edit_by,
            CURRENT_TIMESTAMP
        );
    END IF;

    -- Insert into TB_CENTRAL_SYSTEM_LOG
    INSERT INTO applications.tb_central_system_log (
        log_id, app_id, system_name, trace_id, record_type, record_key,
        record_value1, record_value2, record_value3, record_value4,
        record_value5, record_message, record_note, edit_by, edit_time
    )
    VALUES (
        log_id,
        app_id,
        COALESCE(CURRENT_DATABASE(), 'Unknown'),
        gen_random_uuid()::STRING,
        'GOOD',
        uid,
        'Account enabled: ' || is_enabled,
        'User full name: ' || first_name || ' ' || last_name,
        'Identity 1: ' || cloud_sharp_provider || '/' || username,
        'Identity 2: ' || identity_provider || '/' || username,
        'Account added by: ' || edit_by,
        'SQL Transaction; Create new app user with identity;',
        '',
        edit_by,
        CURRENT_TIMESTAMP
    );

END;
$$;
-- +goose StatementEnd



-- +goose Down
DROP PROCEDURE IF EXISTS auth.add_app_user;

DROP FUNCTION IF EXISTS auth.get_teams_by_user;
DROP FUNCTION IF EXISTS auth.get_app_identity_user_profile_headers_by_team;
DROP FUNCTION IF EXISTS auth.get_app_identity_user_profile_headers_by_provider;
DROP FUNCTION IF EXISTS auth.get_app_identity_user_profile_header;
DROP TYPE IF EXISTS auth.rec_app_identity_user_profile_header;

DROP TABLE IF EXISTS auth.tb_app_user_team;
DROP TABLE IF EXISTS auth.tb_app_team;
DROP TABLE IF EXISTS auth.tb_app_user_identity_delete_log;
DROP TABLE IF EXISTS auth.tb_app_user_identity;
DROP TABLE IF EXISTS auth.tb_app_user;

DROP SCHEMA IF EXISTS auth;

