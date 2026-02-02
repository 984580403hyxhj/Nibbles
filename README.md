# ⚡ LightningCatcher (Nibbles)

一款 iOS 知识卡片应用 —— 输入任意文章链接，AI 自动提取核心知识点，生成可滑动浏览的精美卡片，并支持 Socratic 对话式深度学习。

## 功能

- **一键提取** — 粘贴文章 URL（支持微信公众号、网页文章等），后端自动抓取并用 AI 生成多层级知识卡片
- **卡片浏览** — 垂直滑动翻阅知识卡片，支持 3D 翻转查看详情
- **Socratic 对话** — 针对每张卡片内容，与 AI 进行苏格拉底式问答，深度理解知识点
- **知识库** — 所有处理过的文章自动归档，随时回顾

## 架构

```
┌─────────────────┐         ┌──────────────────────┐
│   iOS App       │  HTTP   │   FastAPI Backend     │
│   (SwiftUI)     │ ◄─────► │   (Python)            │
│                 │         │                        │
│  • KnowledgeFeed│         │  • URL → 内容抓取      │
│  • 3D Card View │         │  • DeepSeek V3.2 生成  │
│  • Socratic Chat│         │  • 异步任务队列         │
└─────────────────┘         └──────────────────────┘
```

### 前端 (iOS / SwiftUI)

| 文件 | 说明 |
|------|------|
| `ContentView.swift` | 主界面，URL 输入 + Tab 导航 |
| `KnowledgeFeedView.swift` | 知识卡片 Feed + Socratic 聊天 |
| `TaskPoller.swift` | 任务提交与轮询（5s 间隔） |
| `Models.swift` | 数据模型（KnowledgeCard, PendingTask 等） |
| `Theme.swift` | 全局主题样式 |

### 后端 (Python / FastAPI)

| 文件 | 说明 |
|------|------|
| `server.py` | API 服务：任务提交、状态查询、聊天、健康检查 |
| `deploy.sh` | 一键部署脚本（systemd + 日志） |

**API 端点：**

| 方法 | 路径 | 功能 |
|------|------|------|
| POST | `/submit_task` | 提交文章 URL，返回 task_id |
| GET | `/task/{id}` | 查询任务状态和结果 |
| POST | `/chat` | Socratic 对话 |
| GET | `/health` | 健康检查 |

## 技术栈

- **前端**: Swift 5 / SwiftUI / iOS 17+
- **后端**: Python 3 / FastAPI / Uvicorn
- **AI 模型**: DeepSeek V3.2（火山引擎 API）
- **内容抓取**: Jina Reader API
- **部署**: Volcengine ECS / systemd

## 部署

```bash
# 部署后端到服务器
cd Backend
chmod +x deploy.sh
./deploy.sh            # 部署并重启
./deploy.sh --status   # 查看状态
./deploy.sh --logs     # 查看实时日志
```

## 日志

服务器日志位于 `/var/log/lightning/`：
- `server.log` — 全量日志
- `error.log` — 仅错误
- `requests.log` — API 请求记录

## License

MIT
