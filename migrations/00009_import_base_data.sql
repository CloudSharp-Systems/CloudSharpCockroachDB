-- +goose envsub on
-- REMINDER: Run this migration with the command IDAPI_CRDB_URI="$DEV_URI" GCP_CRED="...your gcp cloud storage access credentials..." go run main.go migrate up


-- +goose Up
IMPORT INTO applications.tb_app CSV DATA('gs://temp_db_csv/tb_app.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO applications.tb_app_data_control CSV DATA('gs://temp_db_csv/tb_app_data_control.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO applications.tb_central_system_log CSV DATA('gs://temp_db_csv/tb_central_system_log.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO applications.tb_program_status CSV DATA('gs://temp_db_csv/tb_program_status.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO auth.tb_app_user CSV DATA('gs://temp_db_csv/tb_app_user.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO auth.tb_app_user_identity CSV DATA('gs://temp_db_csv/tb_app_user_identity.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO auth.tb_app_user_identity_delete_log CSV DATA('gs://temp_db_csv/tb_app_user_identity_delete_log.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO auth.tb_app_team CSV DATA('gs://temp_db_csv/tb_app_team.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO auth.tb_app_user_team CSV DATA('gs://temp_db_csv/tb_app_user_team.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO external_stackexchange.tb_cs_educator_posts CSV DATA('gs://temp_db_csv/tb_cs_educator_posts.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO external_stackexchange.tb_cs_educator_raw CSV DATA('gs://temp_db_csv/tb_cs_educator_raw.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO products.tb_server CSV DATA('gs://temp_db_csv/tb_server.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO products.tb_test_graph_edge CSV DATA('gs://temp_db_csv/tb_test_graph_edge.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO network.tb_website CSV DATA('gs://temp_db_csv/tb_website.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO network.tb_website_host CSV DATA('gs://temp_db_csv/tb_website_host.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO network.tb_host_status_log CSV DATA('gs://temp_db_csv/tb_host_status_log.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO network.tb_user_session CSV DATA('gs://temp_db_csv/tb_user_session.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO network.tb_user_session_item CSV DATA('gs://temp_db_csv/tb_user_session_item.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO network.tb_user_session_history_log CSV DATA('gs://temp_db_csv/tb_user_session_history_log.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO network.tb_user_session_item_history_log CSV DATA('gs://temp_db_csv/tb_user_session_item_history_log.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO interfaces.tb_website_menu_header CSV DATA('gs://temp_db_csv/tb_website_menu_header.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;

IMPORT INTO interfaces.tb_website_menu_item CSV DATA('gs://temp_db_csv/tb_website_menu_item.csv?AUTH=specified&CREDENTIALS=${GCP_CRED}') 
WITH skip = '1', DETACHED;




-- +goose Down
DELETE FROM interfaces.tb_website_menu_item;
DELETE FROM interfaces.tb_website_menu_header;
DELETE FROM network.tb_user_session_item_history_log;
DELETE FROM network.tb_user_session_history_log;
DELETE FROM network.tb_user_session_item;
DELETE FROM network.tb_user_session;
DELETE FROM network.tb_host_status_log;
DELETE FROM network.tb_website_host;
DELETE FROM network.tb_website;
DELETE FROM products.tb_test_graph_edge;
DELETE FROM products.tb_server;
DELETE FROM external_stackexchange.tb_cs_educator_raw;
DELETE FROM external_stackexchange.tb_cs_educator_posts;
DELETE FROM auth.tb_app_user_team;
DELETE FROM auth.tb_app_team;
DELETE FROM auth.tb_app_user_identity_delete_log;
DELETE FROM auth.tb_app_user_identity;
DELETE FROM auth.tb_app_user;
DELETE FROM applications.tb_program_status;
DELETE FROM applications.tb_central_system_log;
DELETE FROM applications.tb_app_data_control;
DELETE FROM applications.tb_app;
