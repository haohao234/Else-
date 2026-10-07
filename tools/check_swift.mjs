#!/usr/bin/env node
// 无 Xcode 环境下的静态结构校验。
//
// 它守不住什么，必须说清楚：语法之外的一切（类型是否真的存在、泛型约束、
// 宏展开、并发隔离）都要编译器才能裁决。这个脚本只拦"实测真炸过的那几类"。
//
// 用法：node tools/check_swift.mjs
//
// 开发这个脚本时踩到的两个坑，改它之前先读：
//   1. 计算属性不是存储属性。只按 `private var xxx` 抓会把 `private var bg: Color { ... }`
//      误判成"有 private 存储属性" —— 行尾带 `{` 的一律是计算属性，要跳过。
//   2. 调用点取实参标签必须按括号深度为 0 取。否则 `birthDate: month(-27, day: 18)`
//      里的 `day:`、以及三元里的 `.alert :` 都会被当成顶层标签，报一堆假错。
// 判据：校验脚本自己也会误报 —— 先怀疑脚本，再怀疑代码。

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
const problems = [];
const notes = [];

const SYSTEM_TYPES = new Set([
  "Text", "Image", "Button", "Color", "ScrollView", "Divider", "Spacer", "Circle",
  "Capsule", "TextField", "Toggle", "ProgressView", "Label", "SecureField",
  "AnyView", "EmptyView", "Group", "VStack", "HStack", "ZStack", "ForEach",
  "RoundedRectangle", "Rectangle", "Ellipse", "LinearGradient", "AngularGradient",
  "NavigationStack", "List", "Form", "DatePicker", "Picker", "Stepper", "Link",
]);

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (name.endsWith(".swift")) out.push(p);
  }
  return out;
}

// strip() 必须用在每一处文本分析上：只在配平里剥离、没在 import 检查里剥离，
// 就会把"注释里提到某个 API"误判成缺 import。
function strip(src) {
  let s = "";
  let i = 0;
  let inLine = false, inBlock = false, inStr = false, inMulti = false;
  while (i < src.length) {
    const c = src[i], n = src[i + 1];
    if (inLine) { if (c === "\n") { inLine = false; s += c; } i++; continue; }
    if (inBlock) { if (c === "*" && n === "/") { inBlock = false; i += 2; continue; } i++; continue; }
    if (inMulti) { if (src.slice(i, i + 3) === '"""') { inMulti = false; i += 3; continue; } i++; continue; }
    if (inStr) { if (c === "\\") { i += 2; continue; } if (c === '"') inStr = false; i++; continue; }
    if (c === "/" && n === "/") { inLine = true; i += 2; continue; }
    if (c === "/" && n === "*") { inBlock = true; i += 2; continue; }
    if (src.slice(i, i + 3) === '"""') { inMulti = true; i += 3; continue; }
    if (c === '"') { inStr = true; i++; continue; }
    s += c;
    i++;
  }
  return s;
}

/** 取出一段实参文本里**括号深度为 0** 的标签（`label:`），且排除 `.label` 这种成员访问 */
function topLevelLabels(argStr) {
  const labels = [];
  let depth = 0, i = 0;
  while (i < argStr.length) {
    const c = argStr[i];
    if (c === "(" || c === "[" || c === "{") { depth++; i++; continue; }
    if (c === ")" || c === "]" || c === "}") { depth--; i++; continue; }
    if (depth === 0 && /[A-Za-z_]/.test(c)) {
      let j = i;
      while (j < argStr.length && /[A-Za-z0-9_]/.test(argStr[j])) j++;
      const word = argStr.slice(i, j);
      let k = j;
      while (k < argStr.length && /\s/.test(argStr[k])) k++;
      const prevChar = i > 0 ? argStr[i - 1] : " ";
      if (argStr[k] === ":" && prevChar !== ".") labels.push(word);
      i = j;
      continue;
    }
    i++;
  }
  return labels;
}

/** 找出对 Name( ... ) 的所有调用，返回实参文本（按括号配平截取） */
function findCallArgs(src, name) {
  const out = [];
  const re = new RegExp("\\b" + name + "\\s*\\(", "g");
  let m;
  while ((m = re.exec(src))) {
    const open = m.index + m[0].length - 1;
    let depth = 0, i = open;
    for (; i < src.length; i++) {
      if (src[i] === "(") depth++;
      else if (src[i] === ")") { depth--; if (depth === 0) break; }
    }
    if (depth === 0) out.push(src.slice(open + 1, i));
  }
  return out;
}

/** 取出 struct 体：从 `{` 到行首第一个 `}` */
function structBody(bare, startIdx) {
  const rest = bare.slice(startIdx);
  const end = rest.search(/^\}/m);
  return end >= 0 ? rest.slice(0, end) : rest;
}

/** 存储属性的声明顺序（**排除计算属性**：行尾带 `{` 的不是存储属性） */
function storedPropertyOrder(body) {
  const order = [];
  for (const line of body.split("\n")) {
    const m = line.match(/^\s{2,}(?:@\w+\s+)?(?:let|var)\s+([A-Za-z_]\w*)\s*:\s*(.+?)\s*$/);
    if (!m) continue;
    const tail = m[2].trim();
    if (tail.includes("{")) continue;              // 计算属性
    order.push(m[1]);
  }
  return order;
}

const files = walk(join(ROOT, "App"));
let totalLines = 0;
const stripped = new Map();
const topLevelTypes = new Map();

for (const f of files) {
  const raw = readFileSync(f, "utf8");
  totalLines += raw.split("\n").length;
  const bare = strip(raw);
  stripped.set(f, { bare });
  const rel = relative(ROOT, f).replace(/\\/g, "/");

  for (const [open, close, label] of [["{", "}", "花括号"], ["(", ")", "圆括号"], ["[", "]", "方括号"]]) {
    const a = (bare.match(new RegExp("\\" + open, "g")) || []).length;
    const b = (bare.match(new RegExp("\\" + close, "g")) || []).length;
    if (a !== b) problems.push(`${rel}: ${label}不配平  ${a} vs ${b}`);
  }

  for (const m of bare.matchAll(/^(?:public |internal |open )?(struct|class|enum|protocol|actor)\s+([A-Za-z_][A-Za-z0-9_]*)/gm)) {
    if (topLevelTypes.has(m[2])) problems.push(`顶层类型重名：${m[2]}（${topLevelTypes.get(m[2])} 与 ${rel}）`);
    else topLevelTypes.set(m[2], rel);
  }
}

// ---- 框架 import 反查表（每加一个系统 API 就往这里加一行）----
const IMPORT_TABLE = [
  { need: "UIKit", re: /\b(UIImage|UIImagePickerController|UIPasteboard|UIGraphics|UIDevice)\b/ },
  { need: "PhotosUI", re: /\b(PhotosPicker|PhotosPickerItem|PHPickerViewController)\b/ },
  { need: "UserNotifications", re: /\b(UNUserNotificationCenter|UNMutableNotificationContent|UNNotificationRequest|UNNotificationAction|UNNotificationCategory)\b/ },
  { need: "UserNotificationsUI", re: /\bUNNotificationContentExtension\b/ },
  { need: "LocalAuthentication", re: /\b(LAContext|LABiometryType)\b/ },
  { need: "CoreLocation", re: /\b(CLLocationManager|CLCircularRegion)\b/ },
  { need: "BackgroundTasks", re: /\b(BGTaskScheduler|BGAppRefreshTask)\b/ },
  { need: "AVFoundation", re: /\b(AVAudioSession|AVCaptureSession)\b/ },
];
for (const [f, { bare }] of stripped) {
  const rel = relative(ROOT, f).replace(/\\/g, "/");
  const imported = new Set([...bare.matchAll(/^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)/gm)].map((m) => m[1]));
  for (const rule of IMPORT_TABLE) {
    if (rule.re.test(bare) && !imported.has(rule.need)) {
      problems.push(`${rel}: 用到 ${rule.need} 的 API 但没 import ${rule.need}`);
    }
  }
}

// ---- struct 里只要有 private **存储**属性、且另有需要外部传入的存储属性 → 必须手写 init ----
// 表现是"只能在同文件里构造"，要到第一次被别的文件引用时才炸，且报错落在调用方。
for (const [f, { bare }] of stripped) {
  const rel = relative(ROOT, f).replace(/\\/g, "/");
  for (const m of bare.matchAll(/^struct\s+([A-Za-z_][A-Za-z0-9_]*)[^{]*\{/gm)) {
    const body = structBody(bare, m.index + m[0].length);
    const priv = [];
    const internalStored = [];
    for (const line of body.split("\n")) {
      const mm = line.match(/^\s{2,}(?:@(\w+)\s+)?(private\s+)?(let|var)\s+([A-Za-z_]\w*)\s*:\s*(.+?)\s*$/);
      if (!mm) continue;
      const [, , isPrivate, , name, tail] = mm;
      if (tail.trim().includes("{")) continue;                 // 计算属性
      if (/private\s*\(set\)/.test(line)) { internalStored.push(name); continue; }
      if (isPrivate) priv.push(name); else internalStored.push(name);
    }
    const hasInit = /\binit\s*\(/.test(body);
    // 只有当"别人需要传参构造它"时才是真问题；全是私有状态（SwiftUI 视图常态）不算。
    if (priv.length > 0 && internalStored.length > 0 && !hasInit) {
      problems.push(`${rel}: struct ${m[1]} 有 private 存储属性（${priv.join(", ")}）又有外部传入的属性，却没有手写 init —— 逐成员初始化器会降级成 private`);
    }
  }
}

// ---- 自定义 View 类型是否都有定义 ----
// 注意：这里要用「含嵌套类型」的全量集合。顶层类型集合只认行首无缩进的定义，
// 而 `DS.ShadowSpec` 这类嵌套类型不在里面 —— 拿顶层集合去查会报一片假提示，
// 而假提示会训练人忽略提示。
const allTypeNames = new Set(topLevelTypes.keys());
for (const [, { bare }] of stripped) {
  for (const m of bare.matchAll(/\b(?:struct|class|enum|protocol|actor)\s+([A-Za-z_][A-Za-z0-9_]*)/g)) {
    allTypeNames.add(m[1]);
  }
}

const viewRefs = new Set();
for (const [, { bare }] of stripped) {
  for (const m of bare.matchAll(/\b([A-Z][A-Za-z0-9_]*(?:View|Bar|Chip|Tile|Row|Orb|Block|Progress|Chart|Header|Title|Field|State|Card|Button|Spec|Tone))\b/g)) {
    viewRefs.add(m[1]);
  }
}
for (const ref of viewRefs) {
  if (!allTypeNames.has(ref) && !SYSTEM_TYPES.has(ref)) {
    notes.push(`引用了未在本工程定义的类型：${ref}（若为系统类型请加白名单）`);
  }
}

// ---- 已知的跨编译器版本陷阱：指向元组成员的 key path ----
// `ForEach(Array(x.enumerated()), id: \.offset)` 流传极广，但 Swift 不支持指向**元组成员**的
// key path。换个编译器版本就炸，而且报错指向 ForEach，让人一脸问号。
function checkTupleKeyPath(src) {
  return /Array\([^()]*\.enumerated\(\)\)/.test(src) && /id:\s*\\\.(offset|element)\b/.test(src);
}

// ---- 泛型约束把 View 泛型钉在具体类型上 ----
// 例：`extension X where Trailing == Color` + 闭包 `{ Color.clear.frame(...) }`。
// 声明单看完全合理，但 ViewBuilder 闭包产出的是**修饰后的 View**，不是 Color → 推不出来。
// 默认值请用 EmptyView。
function checkConcreteViewConstraint(src) {
  return /where\s+\w+\s*==\s*(?:Color|Image|Text|Button|Label|Divider|Capsule|Circle)\b/.test(src);
}

for (const [f, { bare }] of stripped) {
  const rel = relative(ROOT, f).replace(/\\/g, "/");
  if (checkTupleKeyPath(bare)) {
    problems.push(`${rel}: 用了 Array(...enumerated()) + id: \\.offset/\\\\.element —— 指向元组成员的 key path 不受支持；改用 id: \\.self 或让元素 Identifiable`);
  }
  if (checkConcreteViewConstraint(bare)) {
    problems.push(`${rel}: 把 View 泛型钉在具体类型上（如 where T == Color）—— ViewBuilder 闭包产出的是修饰后的 View，通常推不出来`);
  }
}

// ---- 自测：新判据必须能对反例报出来，否则就是恒真空转 ----
// 用法：node tools/check_swift.mjs --selftest
if (process.argv.includes("--selftest")) {
  const cases = [
    ["元组 key path（反例）", checkTupleKeyPath("ForEach(Array(items.enumerated()), id: \\.offset) { i, x in }"), true],
    ["元组 key path（干净）", checkTupleKeyPath("ForEach(items.indices, id: \\.self) { i in }"), false],
    ["泛型钉死具体 View（反例）", checkConcreteViewConstraint("extension Foo where Trailing == Color {"), true],
    ["泛型钉死具体 View（干净）", checkConcreteViewConstraint("extension Foo where Trailing == EmptyView {"), false],
  ];
  let bad = 0;
  console.log("=== 判据自测 ===");
  for (const [name, got, want] of cases) {
    const ok = got === want;
    if (!ok) bad++;
    console.log(`  ${ok ? "PASS" : "FAIL"}  ${name}   期望 ${want} / 实得 ${got}`);
  }
  console.log(bad === 0 ? "自测全部通过 ✓" : `自测失败 ${bad} 条 ✗`);
  process.exit(bad === 0 ? 0 : 1);
}

// ---- 关键令牌是否落地 ----
const allBare = [...stripped.values()].map((v) => v.bare).join("\n");
for (const [label, re] of [
  ["主色 #B57EDC", /0xB57EDC/],
  ["屏底 #FAF1F5", /0xFAF1F5/],
  ["主色浅底 #F6E4F0", /0xF6E4F0/],
  ["警示 #D9736B", /0xD9736B/],
  ["柔粉阴影基色 #BF8CAD", /0xBF8CAD/],
]) {
  if (!re.test(allBare)) problems.push(`令牌缺失：${label}`);
}
// 画布上的"奶油粉紫"不该混进其它版本的主色（防旧版回流）
for (const [label, re] of [
  ["旧版紫调主色 #5B47D6（v6）", /0x5B47D6/],
  ["旧版碧绿主色 #1F9C8A", /0x1F9C8A/],
]) {
  if (re.test(allBare)) problems.push(`旧版配色回流：${label} —— 现行是奶油粉紫 #B57EDC`);
}

// ---- 逐成员初始化器：实参顺序必须是存储属性声明顺序的子序列 ----
let orderChecked = 0;
for (const [f, { bare }] of stripped) {
  const rel = relative(ROOT, f).replace(/\\/g, "/");
  for (const m of bare.matchAll(/^struct\s+([A-Za-z_][A-Za-z0-9_]*)[^{]*\{/gm)) {
    const name = m[1];
    const order = storedPropertyOrder(structBody(bare, m.index + m[0].length));
    if (order.length < 2) continue;
    for (const [, { bare: other }] of stripped) {
      for (const args of findCallArgs(other, name)) {
        const labels = topLevelLabels(args);
        if (labels.length === 0) continue;
        orderChecked++;
        let cursor = -1, ok = true;
        for (const lb of labels) {
          const at = order.indexOf(lb, cursor + 1);
          if (at < 0) { ok = false; break; }
          cursor = at;
        }
        if (!ok) {
          problems.push(`${rel}: ${name}(...) 的实参顺序不是存储属性声明顺序的子序列 —— 实参 [${labels.join(", ")}] / 声明 [${order.join(", ")}]`);
        }
      }
    }
  }
}

console.log(`扫描 ${files.length} 个 Swift 文件 / ${totalLines} 行，顶层类型 ${topLevelTypes.size} 个，检查 ${orderChecked} 处构造调用`);
if (notes.length) {
  console.log("\n提示（不判失败）：");
  for (const n of notes) console.log("  · " + n);
}
if (problems.length) {
  console.log(`\n发现 ${problems.length} 个问题：`);
  for (const p of problems) console.log("  ✗ " + p);
  process.exit(1);
}
console.log("\n✓ 静态结构校验通过");
console.log("  注意：这**不**代表能编译 —— 只代表没踩到已知的那几类坑。");
