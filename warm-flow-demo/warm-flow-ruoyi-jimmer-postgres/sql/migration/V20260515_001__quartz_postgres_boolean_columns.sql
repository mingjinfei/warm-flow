-- Purpose: Align existing Quartz tables with org.quartz.impl.jdbcjobstore.PostgreSQLDelegate.
-- Scope: QRTZ_JOB_DETAILS, QRTZ_FIRED_TRIGGERS, QRTZ_SIMPROP_TRIGGERS boolean columns and standard runtime indexes.
-- Rollback: Change the same columns back to varchar(1) with a CASE expression if the application is rolled back to a non-PostgreSQL Quartz delegate.
-- Validation:
--   select table_name, column_name, data_type
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name in ('qrtz_job_details','qrtz_fired_triggers','qrtz_simprop_triggers')
--     and column_name in ('is_durable','is_nonconcurrent','is_update_data','requests_recovery','bool_prop_1','bool_prop_2')
--   order by table_name, column_name;
\set ON_ERROR_STOP on
BEGIN;

ALTER TABLE qrtz_job_details
    ALTER COLUMN is_durable TYPE boolean USING is_durable::boolean,
    ALTER COLUMN is_nonconcurrent TYPE boolean USING is_nonconcurrent::boolean,
    ALTER COLUMN is_update_data TYPE boolean USING is_update_data::boolean,
    ALTER COLUMN requests_recovery TYPE boolean USING requests_recovery::boolean;

ALTER TABLE qrtz_fired_triggers
    ALTER COLUMN is_nonconcurrent TYPE boolean USING is_nonconcurrent::boolean,
    ALTER COLUMN requests_recovery TYPE boolean USING requests_recovery::boolean;

ALTER TABLE qrtz_simprop_triggers
    ALTER COLUMN bool_prop_1 TYPE boolean USING bool_prop_1::boolean,
    ALTER COLUMN bool_prop_2 TYPE boolean USING bool_prop_2::boolean;

-- These are the standard Quartz PostgreSQL indexes. They are idempotent so the
-- migration can be reviewed/replayed safely across shared dev and CI databases.
CREATE INDEX IF NOT EXISTS idx_qrtz_j_req_recovery ON qrtz_job_details (sched_name, requests_recovery);
CREATE INDEX IF NOT EXISTS idx_qrtz_j_grp ON qrtz_job_details (sched_name, job_group);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_j ON qrtz_triggers (sched_name, job_name, job_group);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_jg ON qrtz_triggers (sched_name, job_group);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_c ON qrtz_triggers (sched_name, calendar_name);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_g ON qrtz_triggers (sched_name, trigger_group);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_state ON qrtz_triggers (sched_name, trigger_state);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_n_state ON qrtz_triggers (sched_name, trigger_name, trigger_group, trigger_state);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_n_g_state ON qrtz_triggers (sched_name, trigger_group, trigger_state);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_next_fire_time ON qrtz_triggers (sched_name, next_fire_time);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_nft_st ON qrtz_triggers (sched_name, trigger_state, next_fire_time);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_nft_misfire ON qrtz_triggers (sched_name, misfire_instr, next_fire_time);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_nft_st_misfire ON qrtz_triggers (sched_name, misfire_instr, next_fire_time, trigger_state);
CREATE INDEX IF NOT EXISTS idx_qrtz_t_nft_st_misfire_grp ON qrtz_triggers (sched_name, misfire_instr, next_fire_time, trigger_group, trigger_state);
CREATE INDEX IF NOT EXISTS idx_qrtz_ft_trig_inst_name ON qrtz_fired_triggers (sched_name, instance_name);
CREATE INDEX IF NOT EXISTS idx_qrtz_ft_inst_job_req_rcvry ON qrtz_fired_triggers (sched_name, instance_name, requests_recovery);
CREATE INDEX IF NOT EXISTS idx_qrtz_ft_j_g ON qrtz_fired_triggers (sched_name, job_name, job_group);
CREATE INDEX IF NOT EXISTS idx_qrtz_ft_jg ON qrtz_fired_triggers (sched_name, job_group);
CREATE INDEX IF NOT EXISTS idx_qrtz_ft_t_g ON qrtz_fired_triggers (sched_name, trigger_name, trigger_group);
CREATE INDEX IF NOT EXISTS idx_qrtz_ft_tg ON qrtz_fired_triggers (sched_name, trigger_group);

COMMIT;
