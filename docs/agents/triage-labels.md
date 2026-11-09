# 分诊标签

| 标准角色 | 本地标签 | 含义 |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | 等待维护者评估 |
| `needs-info` | `needs-info` | 等待报告者补充信息 |
| `ready-for-agent` | `ready-for-agent` | 规格完整，可交由代理实施 |
| `ready-for-human` | `ready-for-human` | 需要人工实施 |
| `wontfix` | `wontfix` | 决定不处理 |

技能要求应用某个分诊角色时，使用表中对应的本地标签，并写入任务文件的 `Status:` 行。

后续调整标签名称时，修改本表的本地标签列。
