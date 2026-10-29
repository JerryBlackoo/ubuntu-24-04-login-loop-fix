# Ubuntu 24.04 登录循环问题排查与修复记录 (Login Loop Fix)

记录一次在 **Ubuntu 24.04.3 LTS** 环境下出现的 GDM 登录循环（Login Loop）故障的完整排查过程、应急修复方案与后续根因定位指南。

---

## 1. 故障现象与环境

### 现象描述
* **故障日期**：2026-10-29
* **表现**：开机进入 GDM 登录界面，选择用户并输入正确密码后：
  1. 密码正常被系统接受；
  2. 屏幕短暂黑屏或闪烁；
  3. 几秒后重新被踢回 GDM 登录界面；
  4. 无法进入 GNOME 桌面环境。

### 系统环境配置
* **OS**: Ubuntu 24.04.3 LTS
* **Kernel**: `6.14.0-37-generic`
* **Desktop**: GNOME 46
* **Display Manager**: GDM3
* **GPU**: Intel Raptor Lake-P Iris Xe Graphics

---

## 2. 排查阶段与证据链

### 阶段一：排除用户名和密码问题
通过快捷键切换到字符控制台：
```bash
Ctrl + Alt + F3   # 笔记本若冲突可使用 Ctrl + Alt + Fn + F3
```
在 TTY3 登录测试：
```text
login: Jerry
Password:
Welcome to Ubuntu 24.04.3 LTS
Jerry@Jerry-XiaoXinPro-14-IRH8:~$
```
* **结论**：账户与密码完全正常，PAM 认证成功。故障发生在「认证通过后启动图形桌面会话」阶段。

---

### 阶段二：检查磁盘空间配额
在 TTY 中检查文件系统挂载与剩余容量：
```bash
df -h
```
主要结果：
```text
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p7  109G   71G   32G  70% /
/dev/nvme0n1p5  642G  627G   15G  98% /media/Jerry/Data
```
* **结论**：根分区 `/` 剩余 32 GB（70%），未发生满盘情况。排除了因为根分区耗尽导致 GNOME / XDG 无法写入临时文件、套接字的问题。

---

### 阶段三：检查 GDM 服务与日志
检查显示管理器服务状态：
```bash
systemctl status gdm3 --no-pager -l
```
服务状态为 `active (running)`，但日志中出现关键报错：
```text
Session never registered, failing
Failed to start org.gnome.Shell@wayland.service
GNOME Shell on Wayland
```
* **链路分析**：
  $$\text{GDM 正常} \longrightarrow \text{用户认证通过} \longrightarrow \text{尝试拉起 GNOME Wayland Session} \longrightarrow \text{GNOME Shell 崩溃/失败} \longrightarrow \text{Session 注册超时退出} \longrightarrow \text{回到 GDM}$$
* **结论**：问题已经精确缩小到 **GNOME Shell / Mutter / Wayland 会话层**，显示管理器 GDM 本身未损坏。

---

### 阶段四：切换 Xorg 会话验证 (A/B 对比)
返回 GDM 图形界面：
1. 选中用户；
2. 点击右下角齿轮（设置图标）；
3. 将会话由默认的 **Ubuntu** 切换为 **Ubuntu on Xorg**；
4. 输入密码登录。

**结果**：成功进入桌面！
```bash
echo $XDG_SESSION_TYPE
# 输出: x11
```

#### 对比诊断矩阵
| 检查项 | 状态 | 说明 |
| :--- | :---: | :--- |
| 用户凭证与 PAM 认证 | ✅ 正常 | TTY 及 GDM 密码均通过 |
| 根文件系统 `/` 空间 | ✅ 正常 | 剩余 32GB (70%) |
| GDM3 服务 | ✅ 正常 | 正常监听并管理会话 |
| GNOME on Xorg (X11) | ✅ 正常 | 桌面、扩展、应用运行正常 |
| **GNOME on Wayland** | ❌ **失败** | `org.gnome.Shell@wayland.service` 启动失败 |

---

### 阶段五：GPU 与显示驱动栈检查
```bash
lspci | grep -Ei 'vga|3d|display'
# 输出: Intel Corporation Raptor Lake-P [Iris Xe Graphics]
```
* **结论**：本机仅搭载 Intel 集显，排除了 NVIDIA 专有驱动、PRIME 显卡切换或混合双显卡兼容性干扰。
* **涉及图形技术栈**：
  $$\text{Intel Iris Xe} \longrightarrow \text{i915 / xe 内核驱动} \longrightarrow \text{Mesa / GBM / EGL} \longrightarrow \text{Mutter} \longrightarrow \text{GNOME Shell (Wayland)}$$

---

## 3. 最终判定与修复措施

### 判定
> GDM 用户认证成功，但 GNOME Shell 的 Wayland 会话在启动时由于 Mutter / Wayland / 驱动栈协同问题瞬间崩溃或无法向 systemd 注册，导致 GDM 回滚重置登录界面。

### 当前解决方案（立即可用）
在 GDM 登录界面齿轮中选用 **Ubuntu on Xorg**。
* **性质**：Xorg 为官方完整支持的标准显示服务，属于稳定可用的生产级会话。
* **可用性**：开发、浏览器、Docker、VS Code / Cursor、终端等所有工作均可正常进行。无需重装系统。

### 避免的高风险操作（守住底线）
排查中严格避免了以下盲目破坏性操作：
- ❌ 未执行 `sudo chown -R ...` 篡改整个 `$HOME` 目录权限；
- ❌ 未盲目重装 GNOME Desktop、GDM、Mesa 或降级内核；
- ❌ 未在 `/etc/gdm3/custom.conf` 中直接全局强制永久关闭 Wayland，保留了排查根因的完整现场。

---

## 4. 后续深入定位指南

### 1. 时间窗口日志分析
必须根据故障发生的精确时间窗口过滤日志，防止被成功登录后的正常日志覆盖：
```bash
# 系统级 Mutter / DRM / GDM 日志
journalctl -b \
  --since "13:03:30" \
  --until "13:05:10" \
  --no-pager | grep -Ei 'gnome-shell|mutter|wayland|gdm|drm|i915|xe|segfault|core|failed'

# 用户级 GNOME 会话日志
journalctl --user -b \
  --since "13:03:30" \
  --until "13:05:10" \
  --no-pager | grep -Ei 'gnome-shell|mutter|wayland|failed|error|segfault|core'
```

### 2. 避免日志误判
在成功进入 X11 桌面后，日志可能包含：
* `JS ERROR: TypeError: this.actor is null`
* `MetaWindowActorX11` / `MetaSurfaceActorX11`

这些属于 X11 运行期的普通前端告警，**并非** 导致 Wayland 崩溃的根本原因。必须以时间戳对齐失败瞬间的崩溃信息（如 `segfault`、`core dump`、`libEGL/Mesa`）。

### 3. 排查脚本工具
仓库内提供辅助收集与安全检查脚本 [`scripts/collect-wayland-logs.sh`](file:///scripts/collect-wayland-logs.sh)：
```bash
./scripts/collect-wayland-logs.sh "10 minutes ago" "now" "wayland_debug.log"
```

---

## 5. 安全与运维规范

在排查系统日志时，若终端中后台运行过网络工具（如 sing-box、clash、v2ray 等），日志可能夹带敏感凭据（UUID、Password、Private Key、Reality 参数等）。

**规范做法**：
1. 先重定向到本地文件：
   ```bash
   journalctl ... > log.txt
   ```
2. 检查敏感字样：
   ```bash
   grep -Ei 'password|token|uuid|private|secret|vless|vmess' log.txt
   ```
3. 严禁直接公开包含未经脱敏凭据的终端截屏或原始日志文本。
