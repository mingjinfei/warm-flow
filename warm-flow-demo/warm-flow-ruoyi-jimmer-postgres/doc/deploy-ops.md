# RuoYi + Warm-Flow Jimmer/PostgreSQL 部署与运维说明

本文面向 `warm-flow-jimmer-demo` 后台的开发/演示环境。默认复用 `192.168.2.226` 上 `dev-postgres` 与 `dev-redis`，不在部署脚本中删除或重建已有数据。

## 默认访问

- Web/API: <http://192.168.2.226:18080/>
- Health: <http://192.168.2.226:18080/health>
- 默认账号: `admin/admin123`
- 默认后端端口: `18080`

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SERVER_PORT` | `18080` | 宿主机访问端口；容器内固定映射到 `18080`。 |
| `SPRING_PROFILES_ACTIVE` | `druid` | Spring profile，加载 `application-druid.yml`。 |
| `RUOYI_PROFILE` | `/home/ruoyi/uploadPath` | 上传文件目录，compose 会挂载为持久化卷。 |
| `WARM_FLOW_DB_URL` | `jdbc:postgresql://dev-postgres:5432/warm_flow_jimmer_demo` | PostgreSQL JDBC URL。 |
| `WARM_FLOW_DB_USERNAME` | `warm_flow_jimmer_demo` | PostgreSQL 用户。 |
| `WARM_FLOW_DB_PASSWORD` | 空 | PostgreSQL 密码，按目标环境设置。 |
| `REDIS_HOST` | `dev-redis` | Redis 主机。 |
| `REDIS_PORT` | `6379` | Redis 端口。 |
| `REDIS_DATABASE` | `0` | Redis DB。 |
| `REDIS_PASSWORD` | 空 | Redis 密码，按目标环境设置。 |
| Docker network | `dev-infra` | 应用、`dev-postgres`、`dev-redis` 共享的外部 Docker 网络。 |
| `RUOYI_TOKEN_SECRET` | 无 | 必填 JWT 密钥；部署前必须设置 32 位以上随机值，示例值会被启动守卫拒绝。 |
| `RUOYI_TOKEN_EXPIRE_MINUTES` | `120` | token 有效期。 |
| `RUOYI_LOG_LEVEL` | `info` | RuoYi 业务日志级别；临时排查才改为 `debug`。 |
| `WARM_FLOW_LOG_LEVEL` | `info` | Warm-Flow 日志级别；临时排查才改为 `debug`。 |
| `SPRING_DEVTOOLS_RESTART_ENABLED` | `false` | devtools restart 默认关闭，避免生产运行期热重启。 |
| `SWAGGER_ENABLED` | `false` | Swagger 默认关闭；仅内网调试时临时开启。 |
| `DRUID_WEB_STAT_ENABLED` | `false` | Druid Web 统计过滤器默认关闭。 |
| `DRUID_STAT_VIEW_ENABLED` | `false` | Druid 控制台默认关闭。 |
| `DRUID_PUBLIC_ACCESS_ENABLED` | `false` | 即使启用 Druid 控制台，也默认不匿名放行 `/druid/**`。如需原 Druid 登录页调试，需显式开启并配置白名单/密码。 |
| `DRUID_ALLOW` | `127.0.0.1` | Druid 控制台白名单，启用控制台时必须按内网来源收敛。 |
| `DRUID_LOGIN_USERNAME` / `DRUID_LOGIN_PASSWORD` | 空 | Druid 控制台账号密码；启用控制台时必须设置强口令。 |
| `JIMMER_SHOW_SQL` | `false` | 是否输出 Jimmer SQL。 |
| `JIMMER_PRETTY_SQL` | `false` | 是否格式化 SQL。 |

建议在服务器上创建 `.env`，不要把真实密码提交进 Git：

```sh
SERVER_PORT=18080
SPRING_PROFILES_ACTIVE=druid
WARM_FLOW_DB_URL=jdbc:postgresql://dev-postgres:5432/warm_flow_jimmer_demo
WARM_FLOW_DB_USERNAME=warm_flow_jimmer_demo
WARM_FLOW_DB_PASSWORD=change-me
REDIS_HOST=dev-redis
REDIS_PORT=6379
REDIS_DATABASE=0
REDIS_PASSWORD=change-me-if-any
# 先在 shell 中生成密钥，再把输出写成 RUOYI_TOKEN_SECRET=<生成值>
openssl rand -base64 48 | tr -d '\n'
RUOYI_TOKEN_SECRET=<paste-generated-secret>
SWAGGER_ENABLED=false
DRUID_STAT_VIEW_ENABLED=false
```


## 生产安全基线

- 部署前必须设置强随机 `RUOYI_TOKEN_SECRET`；空值、示例值和过短值会触发启动失败。只有本地临时调试才允许显式设置 `RUOYI_ALLOW_INSECURE_TOKEN_SECRET=true`。部署脚本会在前端构建前校验该变量，避免长时间构建后才失败。
- 默认日志级别为 `info`，`devtools.restart`、Swagger 与 Druid 控制台默认关闭，避免把调试入口暴露到共享环境。
- 如需临时开启 Swagger，设置 `SWAGGER_ENABLED=true` 后只在受控内网使用，排查后关闭。
- 如需临时开启 Druid，至少设置 `DRUID_STAT_VIEW_ENABLED=true`、强口令 `DRUID_LOGIN_USERNAME/DRUID_LOGIN_PASSWORD`、收敛 `DRUID_ALLOW`；只有确需访问 Druid 自带登录页时才设置 `DRUID_PUBLIC_ACCESS_ENABLED=true`。
- 首次登录后请立即修改默认 `admin/admin123` 密码，并按环境轮换数据库、Redis 与 Druid 口令。
- 保持 `jimmer.database-validation-mode=ERROR`，让实体/schema 漂移在启动阶段 fail fast。

## 初始化数据库

初始化 SQL 已生成在：

- `sql/postgresql/ruoyi-warm-flow-jimmer-postgres.sql`

> 已有环境升级请不要重跑全量初始化脚本；生产、预发、共享开发库的后续变更应放入 `sql/migration/`，规则见 [`../sql/migration/README.md`](../sql/migration/README.md)。

首次部署前在 PostgreSQL 所在主机或可访问 PostgreSQL 的机器执行。示例命令会创建/授权演示库用户并导入 RuoYi、Quartz、Warm-Flow 与示例菜单数据；`ruoyi-warm-flow-jimmer-postgres.sql` 默认只允许空库/空 `public` schema 初始化，检测到已有表会拒绝继续。确需重置演示库时，必须先备份、人工审阅 SQL，并显式传入 `-v allow_destructive_reset=true`。

```sh
# 1) 在维护库创建/确认应用库和用户；app_password 按目标环境替换
psql "postgresql://postgres@192.168.2.226:5432/postgres" \
  -v ON_ERROR_STOP=1 \
  -v app_password='replace-with-strong-password' \
  -f sql/postgresql/00-create-database.sql

# 可选：创建一次性验收库时覆盖库名/用户名，避免影响共享演示库
psql "postgresql://postgres@192.168.2.226:5432/postgres" \
  -v ON_ERROR_STOP=1 \
  -v app_db='warm_flow_jimmer_smoke' \
  -v app_user='warm_flow_jimmer_smoke' \
  -v app_password='replace-with-strong-password' \
  -f sql/postgresql/00-create-database.sql

# 2) 连接应用库导入完整 RuoYi + Quartz + Warm-Flow + 示例数据
psql "postgresql://warm_flow_jimmer_demo@192.168.2.226:5432/warm_flow_jimmer_demo" \
  -v ON_ERROR_STOP=1 \
  -f sql/postgresql/ruoyi-warm-flow-jimmer-postgres.sql

# 只在已备份且确认要重置演示库时使用：
psql "postgresql://warm_flow_jimmer_demo@192.168.2.226:5432/warm_flow_jimmer_demo" \
  -v ON_ERROR_STOP=1 \
  -v allow_destructive_reset=true \
  -f sql/postgresql/ruoyi-warm-flow-jimmer-postgres.sql
```

如果需要重新生成初始化 SQL：

```sh
python3 scripts/generate_pg_init.py
```

## 已有环境升级

已有共享开发库、预发库或生产库升级时，只执行 `sql/migration/` 下经过审阅的增量脚本，禁止对已有库重跑 bootstrap。当前分支包含的增量迁移：

- `sql/migration/V20260515_001__quartz_postgres_boolean_columns.sql`：将既有 `QRTZ_*` 表中 Quartz PostgreSQL delegate 使用的 boolean 字段从 `varchar(1)` 迁移为 PostgreSQL `boolean`，并补齐标准 Quartz 运行态索引。
- `sql/migration/V20260515_002__warm_flow_engine_not_null_columns.sql`：将 Warm-Flow 引擎必填列恢复为 `NOT NULL`，同时保留历史任务 `node_code/node_type` 与 Jimmer 模型一致的可空语义。

示例：

```sh
psql "$APP_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f sql/migration/V20260515_001__quartz_postgres_boolean_columns.sql

psql "$APP_DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f sql/migration/V20260515_002__warm_flow_engine_not_null_columns.sql

psql "$APP_DATABASE_URL" -Atc "
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('qrtz_job_details','qrtz_fired_triggers','qrtz_simprop_triggers')
  and column_name in ('is_durable','is_nonconcurrent','is_update_data','requests_recovery','bool_prop_1','bool_prop_2')
order by table_name, column_name;"
```

## 冷启动验收

冷启动验收脚本：`scripts/cold_start_validate.sh`。它会在 Docker 主机上创建临时 PostgreSQL 库和临时用户，使用应用用户导入 `sql/postgresql/ruoyi-warm-flow-jimmer-postgres.sql`，再启动一个临时应用容器指向该新库并等待 `/health`。脚本默认结束后删除临时容器、临时卷、临时库和临时用户，不会重置共享开发库或生产库。

典型用法：

```sh
# 在可访问 dev-postgres/dev-redis 的 Docker 主机执行；本地构建时默认使用 ruoyi-admin/target/ruoyi-admin.jar
mvn -DskipTests clean package
REDIS_PASSWORD='replace-with-dev-redis-password-if-any' scripts/cold_start_validate.sh
```

如果需要在远程服务器直接复用已部署的 jar，可覆盖 `APP_JAR`：

```sh
APP_JAR=/home/foo/warm-flow-jimmer-demo/app.jar REDIS_PASSWORD='replace-with-dev-redis-password-if-any' scripts/cold_start_validate.sh
```

如需在冷启动实例上继续手工跑 API smoke 或浏览器 E2E，保留临时实例：

```sh
KEEP_COLDSTART=true COLDSTART_PORT=18081 REDIS_PASSWORD='replace-with-dev-redis-password-if-any' scripts/cold_start_validate.sh
REDIS_DATABASE=15 REDIS_PASSWORD='replace-with-dev-redis-password-if-any' python3 scripts/smoke_remote.py --base-url http://127.0.0.1:18081/
WARM_FLOW_BASE=http://127.0.0.1:18081/ REDIS_DATABASE=15 REDIS_PASSWORD='replace-with-dev-redis-password-if-any' scripts/e2e_admin_designer.sh
COLDSTART_ACTION=cleanup scripts/cold_start_validate.sh
```

关键环境变量：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `POSTGRES_CONTAINER` | `dev-postgres` | PostgreSQL Docker 容器名。 |
| `APP_JAR` | `ruoyi-admin/target/ruoyi-admin.jar` | 临时容器挂载运行的应用 jar。 |
| `COLDSTART_PORT` | `18081` | 临时实例宿主机端口。 |
| `REDIS_DATABASE` | `15` | 冷启动实例使用的 Redis DB，避免污染演示 DB 0。 |
| `KEEP_COLDSTART` | `false` | 设为 `true` 时通过 health 后保留临时实例，便于继续验收。 |
| `KEEP_FAILED_COLDSTART` | `false` | 设为 `true` 时失败后保留临时实例和临时库，便于 CI dump logs 后再 cleanup。 |
| `STATE_FILE` | `/tmp/warm-flow-jimmer-coldstart.state` | 保留实例后的清理状态文件。 |

## 构建与容器部署

CI 会先从 `ruoyi-ui` 源码执行 `npm ci --no-audit --no-fund` 与 `npm run build:prod`，再打包后端，确保完整后台源码仍可构建。部署脚本会调用 `scripts/sync_ruoyi_static.sh`，把最新 `ruoyi-ui/dist` 同步到 `ruoyi-admin/src/main/resources/static`，并保留 `static/warm-flow-ui/` 中的 Warm-Flow 设计器静态资源。

在项目根目录执行：

```sh
(cd ruoyi-ui && npm ci --no-audit --no-fund && npm run build:prod)
scripts/sync_ruoyi_static.sh
mvn -DskipTests clean package
docker network inspect dev-infra >/dev/null 2>&1 || docker network create dev-infra
docker compose -f docker-compose.deploy.yml up -d --build
docker compose -f docker-compose.deploy.yml ps
docker logs -f warm-flow-jimmer-demo
```

也可以使用包装脚本：

```sh
bin/deploy_docker.sh
```

重启/停止：

```sh
docker compose -f docker-compose.deploy.yml restart warm-flow-jimmer-demo
docker compose -f docker-compose.deploy.yml stop warm-flow-jimmer-demo
docker compose -f docker-compose.deploy.yml up -d warm-flow-jimmer-demo
```

只查看状态（非破坏性）：

```sh
docker ps --filter name=warm-flow-jimmer-demo
curl -fsS http://192.168.2.226:18080/health
```

## 烟测

### API 烟测

烟测脚本：`scripts/smoke_remote.py`，覆盖：

- `/health`（只暴露 liveness/版本/入口信息，不返回默认账号密码）
- `/warm-flow-ui/index.html`
- `/captchaImage`
- `/login`
- `/getInfo`
- `/getRouters`
- `/system/user/list`
- `/system/role/list`
- `/system/menu/list`
- `/system/dept/list`
- `/system/post/list`
- `/system/dict/type/list`
- `/system/dict/data/list`
- `/system/config/list`
- `/monitor/server`
- `/monitor/cache`
- `/monitor/operlog/list`
- `/monitor/logininfor/list`
- `/monitor/job/list`
- `/tool/gen/list`
- `/flow/definition/list`
- `/flow/form/list`
- `/flow/execute/toDoPage`
- `/flow/execute/donePage`

验证码开启时，脚本会用 `/captchaImage` 返回的 `uuid` 读取 Redis key `captcha_codes:{uuid}`，自动拿到验证码并登录。脚本优先使用 Python `redis` 包，缺失时回退到 `redis-cli`；两者都不可用或 Redis 不可达时，可使用 `--skip-login` 仅验证匿名接口。
在部署机只提供 Redis Docker 容器、宿主机没有 `redis-cli` 时，可增加 `--redis-container dev-redis`，脚本会通过 `docker exec dev-redis redis-cli ...` 读取验证码。

```sh
python3 scripts/smoke_remote.py \
  --base-url http://192.168.2.226:18080/ \
  --username admin \
  --password admin123 \
  --redis-host dev-redis \
  --redis-port 6379 \
  --redis-container dev-redis

# 或
scripts/smoke_remote.sh --base-url http://192.168.2.226:18080/
```

### 浏览器级 E2E

`scripts/e2e_admin_designer.sh` 会在临时目录安装/复用 Playwright，不会把 `node_modules` 或浏览器缓存写入仓库。该验收覆盖两类 API 烟测无法发现的问题：

- 直接刷新完整 RuoYi 管理后台路由仍能渲染 SPA，而不是退回登录页或空白页。
- Warm-Flow 设计器会用当前 `Admin-Token` 覆盖本地陈旧 `Warm-Authorization`，并成功调用 `/warm-flow/query-def`、`/warm-flow/listener-list`。

默认目标为 `http://192.168.2.226:18080/`，账号为 `admin/admin123`。如果 Redis 开启密码，通过环境变量传入，不要写入 Git。当前 CI、远程 smoke 与浏览器 E2E 验收记录见 [`acceptance-jimmer-postgres.md`](acceptance-jimmer-postgres.md)：

```sh
REDIS_PASSWORD='replace-with-dev-redis-password-if-any' scripts/e2e_admin_designer.sh

# 常用覆盖项
WARM_FLOW_BASE=http://192.168.2.226:18080/ WARM_FLOW_USER=admin WARM_FLOW_PASSWORD=admin123 REDIS_HOST=192.168.2.226 REDIS_PORT=6379 REDIS_DATABASE=0 REDIS_PASSWORD='replace-with-dev-redis-password-if-any' scripts/e2e_admin_designer.sh
```

成功时末尾应输出 `bad=[]`。

## 故障排查

### `/health` 不通

1. `docker ps --filter name=warm-flow-jimmer-demo` 确认容器是否运行。
2. `docker logs --tail=200 warm-flow-jimmer-demo` 查看启动异常。
3. 确认端口映射：`docker compose -f docker-compose.deploy.yml ps`。
4. 确认服务器防火墙或安全组允许访问 `18080`。

### 数据库连接失败

1. 核对 `WARM_FLOW_DB_URL/WARM_FLOW_DB_USERNAME/WARM_FLOW_DB_PASSWORD`。
2. 从应用所在主机执行只读连通性检查：`psql "$WARM_FLOW_DB_URL" -c 'select 1'`（JDBC URL 需要换成 psql URL）。
3. 查看 PostgreSQL 是否允许来自容器/宿主机的连接，以及数据库、用户、schema 权限是否已初始化。

### Redis 或验证码登录失败

1. 核对 `REDIS_HOST/REDIS_PORT/REDIS_DATABASE/REDIS_PASSWORD`。
2. 用 `redis-cli -h 192.168.2.226 -p 6379 ping` 检查连通性。
3. 调用 `/captchaImage` 后检查 Redis 是否出现 `captcha_codes:*` key。
4. 烟测机未安装 Python `redis` 包且没有 `redis-cli` 时，先安装任一工具或使用 `--skip-login` 跳过登录类接口。

### 登录失败或账号不可用

1. 确认初始化 SQL 已导入，默认账号为 `admin/admin123`。
2. 如果连续输错导致账号锁定，等待 `user.password.lockTime` 或清理对应 Redis 登录失败 key。
3. 检查系统时间和 token 配置，尤其是 `RUOYI_TOKEN_SECRET` 与 `RUOYI_TOKEN_EXPIRE_MINUTES`。

### 流程列表为空或接口异常

1. 确认初始化 SQL 包含 Warm-Flow 表及示例流程定义。
2. 检查 `/flow/definition/list`、`/flow/form/list` 的响应 code/msg。
3. 打开 `JIMMER_SHOW_SQL=true` 临时查看 SQL，定位字段、表名或权限问题；排查后关闭。
