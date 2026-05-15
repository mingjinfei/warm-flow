-- Purpose: Restore NOT NULL constraints required by Warm-Flow Jimmer engine models.
-- Scope: flow_definition, flow_form, flow_node, flow_skip, flow_instance, flow_task, flow_his_task and flow_user.
-- Rollback: ALTER the same columns DROP NOT NULL if rolling back to the earlier permissive bootstrap.
-- Validation:
--   select table_name, column_name, is_nullable
--   from information_schema.columns
--   where table_schema = 'public'
--     and (table_name, column_name) in (
--       ('flow_definition','flow_code'), ('flow_definition','flow_name'), ('flow_definition','model_value'),
--       ('flow_definition','version'), ('flow_definition','is_publish'), ('flow_definition','activity_status'),
--       ('flow_form','form_code'), ('flow_form','form_name'), ('flow_form','version'), ('flow_form','is_publish'),
--       ('flow_node','node_type'), ('flow_node','definition_id'), ('flow_node','node_code'), ('flow_node','version'),
--       ('flow_skip','definition_id'), ('flow_skip','now_node_code'), ('flow_skip','next_node_code'),
--       ('flow_instance','definition_id'), ('flow_instance','business_id'), ('flow_instance','node_type'),
--       ('flow_instance','node_code'), ('flow_instance','flow_status'), ('flow_instance','activity_status'),
--       ('flow_task','definition_id'), ('flow_task','instance_id'), ('flow_task','node_code'),
--       ('flow_task','node_type'), ('flow_task','flow_status'),
--       ('flow_his_task','definition_id'), ('flow_his_task','instance_id'), ('flow_his_task','task_id'),
--       ('flow_his_task','cooperate_type'), ('flow_his_task','flow_status'),
--       ('flow_user','type'), ('flow_user','associated')
--     )
--   order by table_name, column_name;
\set ON_ERROR_STOP on
BEGIN;

-- Do not invent values for nullable production data. Abort with a precise column
-- name if any existing row would violate the Jimmer nonnull model contract.
DO $$
DECLARE
    required_columns constant text[] := ARRAY[
        'flow_definition.flow_code',
        'flow_definition.flow_name',
        'flow_definition.model_value',
        'flow_definition.version',
        'flow_definition.is_publish',
        'flow_definition.activity_status',
        'flow_form.form_code',
        'flow_form.form_name',
        'flow_form.version',
        'flow_form.is_publish',
        'flow_node.node_type',
        'flow_node.definition_id',
        'flow_node.node_code',
        'flow_node.version',
        'flow_skip.definition_id',
        'flow_skip.now_node_code',
        'flow_skip.next_node_code',
        'flow_instance.definition_id',
        'flow_instance.business_id',
        'flow_instance.node_type',
        'flow_instance.node_code',
        'flow_instance.flow_status',
        'flow_instance.activity_status',
        'flow_task.definition_id',
        'flow_task.instance_id',
        'flow_task.node_code',
        'flow_task.node_type',
        'flow_task.flow_status',
        'flow_his_task.definition_id',
        'flow_his_task.instance_id',
        'flow_his_task.task_id',
        'flow_his_task.cooperate_type',
        'flow_his_task.flow_status',
        'flow_user.type',
        'flow_user.associated'
    ];
    item text;
    table_name text;
    column_name text;
    null_rows bigint;
BEGIN
    FOREACH item IN ARRAY required_columns LOOP
        table_name := split_part(item, '.', 1);
        column_name := split_part(item, '.', 2);
        EXECUTE format('SELECT count(*) FROM %I WHERE %I IS NULL', table_name, column_name) INTO null_rows;
        IF null_rows > 0 THEN
            RAISE EXCEPTION 'Cannot set %.% NOT NULL: % existing null row(s)', table_name, column_name, null_rows;
        END IF;
    END LOOP;
END $$;

ALTER TABLE flow_definition
    ALTER COLUMN flow_code SET NOT NULL,
    ALTER COLUMN flow_name SET NOT NULL,
    ALTER COLUMN model_value SET DEFAULT 'CLASSICS',
    ALTER COLUMN model_value SET NOT NULL,
    ALTER COLUMN "version" SET NOT NULL,
    ALTER COLUMN is_publish SET DEFAULT 0,
    ALTER COLUMN is_publish SET NOT NULL,
    ALTER COLUMN activity_status SET DEFAULT 1,
    ALTER COLUMN activity_status SET NOT NULL;

ALTER TABLE flow_form
    ALTER COLUMN form_code SET NOT NULL,
    ALTER COLUMN form_name SET NOT NULL,
    ALTER COLUMN "version" SET NOT NULL,
    ALTER COLUMN is_publish SET DEFAULT 0,
    ALTER COLUMN is_publish SET NOT NULL;

ALTER TABLE flow_node
    ALTER COLUMN node_type SET NOT NULL,
    ALTER COLUMN definition_id SET NOT NULL,
    ALTER COLUMN node_code SET NOT NULL,
    ALTER COLUMN "version" SET NOT NULL;

ALTER TABLE flow_skip
    ALTER COLUMN definition_id SET NOT NULL,
    ALTER COLUMN now_node_code SET NOT NULL,
    ALTER COLUMN next_node_code SET NOT NULL;

ALTER TABLE flow_instance
    ALTER COLUMN definition_id SET NOT NULL,
    ALTER COLUMN business_id SET NOT NULL,
    ALTER COLUMN node_type SET NOT NULL,
    ALTER COLUMN node_code SET NOT NULL,
    ALTER COLUMN flow_status SET NOT NULL,
    ALTER COLUMN activity_status SET DEFAULT 1,
    ALTER COLUMN activity_status SET NOT NULL;

ALTER TABLE flow_task
    ALTER COLUMN definition_id SET NOT NULL,
    ALTER COLUMN instance_id SET NOT NULL,
    ALTER COLUMN node_code SET NOT NULL,
    ALTER COLUMN node_type SET NOT NULL,
    ALTER COLUMN flow_status SET NOT NULL;

ALTER TABLE flow_his_task
    ALTER COLUMN definition_id SET NOT NULL,
    ALTER COLUMN instance_id SET NOT NULL,
    ALTER COLUMN task_id SET NOT NULL,
    ALTER COLUMN cooperate_type SET DEFAULT 0,
    ALTER COLUMN cooperate_type SET NOT NULL,
    ALTER COLUMN flow_status SET NOT NULL;

ALTER TABLE flow_user
    ALTER COLUMN "type" SET NOT NULL,
    ALTER COLUMN associated SET NOT NULL;

COMMIT;
