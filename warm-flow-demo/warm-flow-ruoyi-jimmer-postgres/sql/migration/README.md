# PostgreSQL 迁移脚本规范

本目录只存放面向已有环境的 **增量迁移脚本**。首次部署、临时验收库、一次性演示库初始化请使用 `../postgresql/` 下的 bootstrap 脚本。

## 脚本边界

- `../postgresql/00-create-database.sql`：创建或确认应用数据库和登录用户，可通过 `app_db/app_user/app_password` 覆盖目标库与账号。
- `../postgresql/ruoyi-warm-flow-jimmer-postgres.sql`：全量初始化 RuoYi、Quartz、Warm-Flow 表结构和演示数据，只适用于空库或临时验收库。
- `sql/migration/`：生产、预发、共享开发库的后续结构和数据变更脚本。

## 安全要求

1. 共享开发库和生产库不得执行破坏性 bootstrap。
2. `ruoyi-warm-flow-jimmer-postgres.sql` 默认检查 `public` schema 中是否已有基础表；非空时会拒绝继续。
3. 只有在已完成备份、人工审阅并确认要重建一次性演示库时，才允许传入：

   ```sh
   psql "$APP_DATABASE_URL" -v ON_ERROR_STOP=1 \
     -v allow_destructive_reset=true \
     -f sql/postgresql/ruoyi-warm-flow-jimmer-postgres.sql
   ```

4. 生产升级必须新增可审阅的增量脚本，禁止修改已在环境执行过的迁移文件。
5. 每个增量脚本必须可重复评审：说明目的、影响表、回滚策略、是否需要停机窗口。
6. 涉及数据修复时，先写只读校验 SQL，再写变更 SQL；变更后保留验收查询。

## 命名建议

使用递增时间戳，保证脚本执行顺序清晰：

```text
V20260515_001__add_business_column.sql
V20260515_002__backfill_business_column.sql
```

脚本头部建议包含：

```sql
-- Purpose: <为什么需要这次迁移>
-- Scope: <影响表/模块>
-- Rollback: <回滚方式或不可回滚原因>
-- Validation: <执行后验收 SQL>
\set ON_ERROR_STOP on
BEGIN;
-- changes here
COMMIT;
```

## 与 Jimmer 校验的关系

应用保持 `jimmer.database-validation-mode=ERROR`。因此迁移必须先在临时库或预发库验证通过，再部署应用；如果表结构与 Jimmer Entity 不一致，应用会启动失败，这是预期的安全保护。
