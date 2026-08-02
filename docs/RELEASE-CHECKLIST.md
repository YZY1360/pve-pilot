# 发布检查清单（Release Checklist）

> 每次发布新版前逐项核对。任何一项未通过 → 修复后再发。

## 隐私与内容检查

- [ ] **无个人/内网地址**：`git grep -n -E "192\.168\.|10\.0\.|10\.1\.|172\.16\."` 无命中
      （文档示例仅允许通用示例如 `192.168.1.10`）
- [ ] **无凭据/密钥**：`git grep -n -E "sk-[A-Za-z0-9]{8,}|ghp_|password\s*=|api[_-]?key"` 无命中
- [ ] **无个人信息**：用户名、邮箱、机器名（如 yzy/fhy）未出现在仓库
- [ ] **无本地路径**：`/root/`、`/home/` 等绝对路径未出现在仓库
- [ ] **无编译产物入库**：`git ls-files | grep -E "build/out|\.fpk$|\.so$"` 为空
      （二进制由 GitHub Actions 构建，不提交）

## 产品检查

- [ ] README 为用户向：无设计约束/构建细节等开发者内容
- [ ] README 中英双版本同步（`README.md` 中文默认 + `README.en.md` 入口）
- [ ] 向导无个人默认值：`fnos/wizard/install`、`fnos/wizard/config` 的 PVE 地址
      `initValue` 为空，仅 placeholder 带通用示例
- [ ] `fnos/cmd/service-setup` 无硬编码 PVE 地址

## 构建与验证

- [ ] `./build/build-nginx.sh --arch both` 成功（或 CI 产物）
- [ ] `./build/package.sh --arch both` 产出 x86 + arm 双架构 fpk
- [ ] `./build/test/local-verify.sh` 全部通过
- [ ] fpk 内含正确版本号（`manifest` 的 `version` 已更新）

## 发布流程

```bash
# 1. 核对以上检查项
# 2. 更新版本号（manifest version + CHANGELOG）
# 3. 打 tag 并推送（触发 GitHub Actions 构建）
git tag v0.1.x && git push origin v0.1.x
# 4. Actions 产出 fpk 并发布到 Release
# 5. 人工抽检：飞牛实机安装 + 向导 + FN Connect 穿透
```
