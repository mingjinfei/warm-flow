# Jimmer/PostgreSQL 生产验收记录

本文记录当前 fork 分支 `codex/jimmer-postgres-production` 的可复现验收状态。文档只保存公开 URL、命令和 CI 结果，不记录数据库或 Redis 密码。

## 验收范围

- 完整 RuoYi 管理后台：登录、用户、角色、菜单、部门、岗位、字典、参数、监控、日志、定时任务、代码生成。
- Warm-Flow 功能：流程定义、表单、待办、已办、设计器 `/warm-flow-ui/index.html`、设计器接口 `/warm-flow/query-def` 与 `/warm-flow/listener-list`。
- PostgreSQL 数据：RuoYi、Quartz、Warm-Flow 与示例业务表统一由 `sql/postgresql/ruoyi-warm-flow-jimmer-postgres.sql` 初始化。
- Quartz 约束：`ruoyi-quartz` 启用 PostgreSQL `LocalDataSourceJobStore`，运行态与 `QRTZ_*` 表保持一致，定时任务状态可跨容器重启保留。
- Jimmer 约束：应用保持 `jimmer.database-validation-mode=ERROR`，启动即校验实体与 PostgreSQL schema 一致性。
- 非破坏性验证：CI 和本地冷启动均使用临时库/临时容器；共享开发库不被重置。

## 当前部署

- 服务器：`192.168.2.226`
- 访问入口：<http://192.168.2.226:18080/>
- Health：<http://192.168.2.226:18080/health>
- 默认账号：`admin/admin123`
- 容器：`warm-flow-jimmer-demo`
- 中间件：复用 `dev-postgres` 与 `dev-redis`

2026-05-15 当前健康检查返回：

```json
{"msg":"操作成功","code":200,"ui":"/index.html","workflowDesigner":"/warm-flow-ui/index.html","auth":"admin / admin123","name":"Warm-Flow Admin Jimmer","version":"3.9.1-jimmer-postgres"}
```

该环境已部署本次最新 jar，并已完成 API smoke 与浏览器 E2E 复测。

## CI 验收

Fork PR：<https://github.com/mingjinfei/warm-flow/pull/1>

| Workflow | Run / Job | 结果 | 覆盖 |
| --- | --- | --- | --- |
| Jimmer PostgreSQL CI | `25911156712` / `Jimmer PostgreSQL integration tests` | success | Jimmer 模块、PostgreSQL 集成、流程审批 smoke |
| RuoYi Jimmer PostgreSQL CI | `25911156734` / `Cold-start bootstrap and API smoke` | success | PR 冷启动、API smoke；PR 中 Browser E2E 按条件跳过 |
| RuoYi Jimmer PostgreSQL CI | `25911155071` / `Cold-start bootstrap and API smoke` | success | push 冷启动、完整 API smoke |
| RuoYi Jimmer PostgreSQL CI | `25911155071` / `Browser E2E smoke` | success | push 浏览器级完整后台路由与设计器 token 自愈 |

> 2026-05-15 已新增 `Build RuoYi UI from source` 门禁：每个 RuoYi Jimmer PostgreSQL CI job 都会执行 `npm ci --no-audit --no-fund` 与 `npm run build:prod`，防止只验证已提交静态产物。`a38f6542` 的后续 CI 暴露 Warm-Flow engine 表 nullability 过宽问题；当前提交用模型一致的 `NOT NULL` bootstrap 与 `V20260515_002` 增量迁移修复，推送后以 PR 最新 run 为准。

关键 CI 命令：

```sh
gh run view 25911155071 --repo mingjinfei/warm-flow --json status,conclusion,jobs,url
gh pr view 1 --repo mingjinfei/warm-flow --json state,url,headRefName,baseRefName,mergeable,statusCheckRollup
```

## 本地与临时库验收（2026-05-15）

提交前本地构建与静态检查：

- `python3 scripts/generate_pg_init.py`：重新生成 `sql/postgresql/ruoyi-warm-flow-jimmer-postgres.sql`。
- 自定义 nullability 校验：Warm-Flow Jimmer nonnull 字段在 generator 与 bootstrap SQL 中保持 `NOT NULL`；业务示例表的 `@Nullable` 字段保持可空。
- Quartz DDL 校验：`QRTZ_*` boolean 字段为 PostgreSQL `boolean`，并包含 20 个标准 Quartz 运行态索引。
- `mvn -q -DskipTests -f pom.xml -pl warm-flow-demo/warm-flow-ruoyi-jimmer-postgres/ruoyi-admin -am clean package`：通过，路径与 GitHub Actions root-pom 构建一致。
- `(cd ruoyi-ui && npm ci --no-audit --no-fund && npm run build:prod)`：通过，仅有既有 asset size warning。
- `git diff --check` 与 `python3 -m py_compile ...`：通过。

远程临时库 cold-start 验收（不重置共享库）：

```sh
ssh workflow-dev-226 'cd /home/foo/warm-flow-jimmer-demo-coldtest; \
  REDIS_PASSWORD=$(docker inspect warm-flow-jimmer-demo --format "{{range .Config.Env}}{{println .}}{{end}}" | sed -n "s/^REDIS_PASSWORD=//p" | tail -n 1); \
  export REDIS_PASSWORD; \
  APP_JAR=/home/foo/warm-flow-jimmer-demo-coldtest/app.jar \
  COLDSTART_PORT=18082 REDIS_DATABASE=14 \
  STATE_FILE=/tmp/warm-flow-jimmer-coldtest-quartz.state \
  scripts/cold_start_validate.sh'
```

2026-05-15 结果：

- `BOOTSTRAP tables=41`、`BOOTSTRAP users=22`、`BOOTSTRAP menus=131`
- `HEALTH_OK {"msg":"操作成功","code":200,...,"version":"3.9.1-jimmer-postgres"}`
- 临时库：`warm_flow_jimmer_cold_20260515183557`
- 临时端口：`18082`
- 结束后脚本自动清理临时容器、临时卷、临时库和临时用户。

## 共享开发库迁移（2026-05-15）

共享开发库未重跑 bootstrap。升级最新 jar 前执行了增量迁移：

```sh
psql -v ON_ERROR_STOP=1 -d warm_flow_jimmer_demo \
  -f sql/migration/V20260515_001__quartz_postgres_boolean_columns.sql

psql -v ON_ERROR_STOP=1 -d warm_flow_jimmer_demo \
  -f sql/migration/V20260515_002__warm_flow_engine_not_null_columns.sql
```

迁移后验证结果：

- `qrtz_job_details.is_durable/is_nonconcurrent/is_update_data/requests_recovery = boolean`
- `qrtz_fired_triggers.is_nonconcurrent/requests_recovery = boolean`
- `qrtz_simprop_triggers.bool_prop_1/bool_prop_2 = boolean`
- `quartz_indexes=20`
- `flow_definition.flow_code=NO`、`flow_user.type=NO`、`flow_user.associated=NO`
- `flow_his_task.flow_status=NO`
- `flow_his_task.node_code=YES`、`flow_his_task.node_type=YES`（与 `FlowHisTaskModel` 的 `@Nullable` 保持一致）


## 远程部署 smoke

在开发机上执行完整 API smoke，脚本通过 Redis 读取验证码并登录默认账号：

```sh
python3 scripts/smoke_remote.py \
  --base-url http://127.0.0.1:18080/ \
  --redis-host 127.0.0.1 \
  --redis-container dev-redis
```

2026-05-15 最新部署后结果：`SMOKE PASS`。

已覆盖接口：

- `health`、`warm-flow-ui.index`、`captcha`、`login`、`getInfo`、`getRouters`
- `system.user.list`、`system.role.list`、`system.menu.list`、`system.dept.list`
- `system.post.list`、`system.dict.type.list`、`system.dict.data.list`、`system.config.list`
- `monitor.server`、`monitor.cache`、`monitor.operlog.list`、`monitor.logininfor.list`、`monitor.job.list`
- `tool.gen.list`
- `flow.definition.list`、`flow.form.list`、`flow.todo.page`、`flow.done.page`
- `warm-flow.query-def`、`warm-flow.listener-list`

## 浏览器 E2E 验收

对远程部署执行浏览器级验收：

```sh
WARM_FLOW_BASE=http://192.168.2.226:18080/ \
REDIS_HOST=192.168.2.226 \
REDIS_PORT=6379 \
REDIS_DATABASE=0 \
REDIS_PASSWORD='从部署环境注入，不写入 Git' \
scripts/e2e_admin_designer.sh
```

2026-05-15 最新部署后结果：`bad=[]`。

已验证浏览器直刷路由：

- `/index`
- `/system/user`
- `/monitor/server`
- `/tool/gen`
- `/flow/definition`
- `/flow/1`

设计器验收结果：

- `Warm-Authorization` 被当前 `Admin-Token` 覆盖：`authOverwritten=true`
- `/warm-flow/listener-list` 返回 HTTP 200、业务 `code=200`
- `/warm-flow/query-def` 返回 HTTP 200、业务 `code=200`
- `pageErrors=0`、`httpErrors=0`

## 操作边界

- 只在 fork 分支 `codex/jimmer-postgres-production` 持续开发与推送。
- 上游 PR `dromara/warm-flow#49` 已关闭，不再恢复或更新。
- 不提交 `.env`、真实密码、`target/`、`node_modules/`、`ruoyi-ui/dist/`、Playwright 缓存或临时运行文件。
- 已有共享开发库或生产库升级只允许使用 `sql/migration/` 增量脚本；全量 bootstrap 仅用于空库、临时库或经备份审阅的一次性演示库。
