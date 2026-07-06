# Azure SA Skills

Azure SA（Solution Architect）日常工作相关的 Hermes / GitHub Copilot skills 集合。每个子目录是一个独立 skill，含 `SKILL.md` 与脚本/模板。

## Skills

### 客户交付 / Partner-facing

- [`billing-assistant/`](./billing-assistant/) — Anchor-based PyMuPDF 工具，把合作伙伴/CSP 寄来的原始账单 PDF（含批注修改要求）改写为客户成品账单，保留版式、支持双币种、自动剥除批注。无 LLM。
- [`openclaw-wechat-deployment/`](./openclaw-wechat-deployment/) — OpenClaw on Azure 部署 + 微信群分享脚本。
- [`wechat-article/`](./wechat-article/) — 把技术内容转成微信公众号短文。

### Azure / Hermes infra

- [`azure-hermes-ghcp-wechat/`](./azure-hermes-ghcp-wechat/) — 在 Azure VM 上部署 Hermes Agent，配置 GitHub Copilot provider 并接入微信。
- [`azure-foundry-quota-tier/`](./azure-foundry-quota-tier/) — Azure AI Foundry 配额 / tier 排查速查。
- [`chorus-azure-deployment/`](./chorus-azure-deployment/) — [Chorus-AIDLC/Chorus](https://github.com/Chorus-AIDLC/Chorus) 部署到 Azure Container Apps（Bicep IaC、PGlite、emptyDir vs azureFile、MCAPS shared-key 绕过）。

### Presentation / 模板

- [`azure-style-presentation/`](./azure-style-presentation/) — Azure 风格 PPT。
- [`ppt-template-strict-offering/`](./ppt-template-strict-offering/) — 严格遵循 offering 模板的 PPT 流程。

### 备份 / Backup

- [`onedrive-azure-backup/`](./onedrive-azure-backup/) — OneDrive 本地文件夹增量备份到 Azure Blob（AzCopy copy 首次全量 + sync 每月增量，排除微信实时缓存）。

---

## 用法

**作为 Hermes skill**：将本仓库 clone 到 `~/.hermes/profiles/<profile>/skills/` 下，或把单个目录复制过去，`skill_view(name='<skill-name>')` 加载。

**作为参考脚本**：每个 skill 目录下都有可独立运行的 `scripts/` 或 `templates/`。
