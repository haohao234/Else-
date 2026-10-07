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

/**
 * 扫描类型体里的**成员声明**（大括号深度 1）。
 *
 * ⚠️ 深度过滤是必须的，两个真实的误判都是它引起的：
 *   · 函数体里的局部变量（`var names: [UUID: String] = [:]`）会被当成存储属性，
 *     于是"有 private 成员 + 有外部传入的成员"凭空成立 → 整屏假报（2026-10-07，SettingsView）；
 *   · 局部变量混进"声明顺序"会让子序列检查变宽 → **假通过**，比误报更危险。
 * 判据自己出错时的代价不比代码出错低，所以抽成函数、进自测。
 */
function memberDeclarations(body, startDepth = 1) {
  const out = [];
  let depth = startDepth;                          // 进入类型体时已经在第 1 层
  for (const line of body.split("\n")) {
    const atDepth = depth;
    for (const ch of line) { if (ch === "{") depth++; else if (ch === "}") depth--; }
    if (atDepth !== startDepth) continue;
    const m = line.match(/^\s{2,}(?:@(\w+)\s+)?(private\s+)?(let|var)\s+([A-Za-z_]\w*)\s*([:=])(.*)$/);
    if (!m) continue;
    const [, , isPrivate, , name, , tail] = m;
    out.push({
      name,
      isPrivate: Boolean(isPrivate),
      // 计算属性的判据：**声明部分（冒号/等号之后）出现 `{`**。
      // ⚠️ 不能用"整行以 `{` 结尾"：单行计算属性 `private var maxValue: Double { max(...) }`
      //    结尾是 `}` 而不是 `{`，那样判会把计算属性当成存储属性（2026-10-07 实测踩到）。
      // ⚠️ 也不能只看"有没有花括号"就完：`private let columns = [GridItem(...)]` 里
      //    方括号中的初始化调用带括号但不带花括号，所以这条判据对它是安全的（判为存储属性，正确）。
      isComputed: tail.includes("{"),
      line: line.trim(),
    });
  }
  return out;
}

/** 存储属性的声明顺序（**排除计算属性**：行尾带 `{` 的不是存储属性） */
function storedPropertyOrder(body) {
  return memberDeclarations(body)
    .filter((d) => !d.isComputed)
    .map((d) => d.name);
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
    // 走统一的成员扫描（含深度过滤 + 计算属性判定，见 memberDeclarations 的注释）
    const members = memberDeclarations(body).filter((d) => !d.isComputed);
    const priv = members.filter((d) => d.isPrivate).map((d) => d.name);
    const internalStored = members.filter((d) => !d.isPrivate).map((d) => d.name);
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

// ---- static 上下文里裸用实例成员（2026-10-07 由 CI 抓到，固化成判据）----
// 例：`static func progressLine(...) { if let n = kittenCount { ... } }` ——
// static 函数里没有实例，直接写实例属性名就报
// `instance member 'kittenCount' cannot be used on type 'BreedingRecord'`。
// 这个错**只有编译器会告诉你**：写的时候看着特别自然（尤其是"为了让编辑器复用
// 而把方法改成 static"的那一刻，很容易漏掉某个字段没提成参数），一次就是一轮 CI 往返。
function checkStaticInstanceUse(bare) {
  const hits = [];
  // 实例成员 = **类型体内**深度 1 的存储属性，且不带 static。
  // ⚠️ 这里必须"逐类型取体"，不能拿整文件按固定深度扫：
  //    文件从深度 0 开始，而 structBody 取出的体从深度 1 开始 —— 共用一个默认值必然错位，
  //    错位的表现是"一个成员都收不到"，也就是这条判据静默失效（自测当场抓到，2026-10-07）。
  const propNames = new Set();
  for (const m of bare.matchAll(/^(?:public |internal |open |final )*(?:struct|class|actor)\s+[A-Za-z_][A-Za-z0-9_]*[^{]*\{/gm)) {
    const body = structBody(bare, m.index + m[0].length);
    for (const d of memberDeclarations(body)) {
      if (d.isComputed) continue;
      if (/\bstatic\b/.test(d.line)) continue;
      propNames.add(d.name);
    }
  }
  // 签名正则：**必须容忍 `throws -> T`**。
  // 原来写成 `\(([\s\S]*?)\)\s*(?:->[^{]*)?\{` —— 遇到
  //   `static func encode(_ value: AppData) throws -> Data {`
  // 那个可选的 `->` 组接不上 `throws`，于是正则回溯，拿**函数体里**的
  // `encoder.encode(value)` 那个 `)` 来收尾，把整个函数体当成参数表 →
  // 凭空报出「encode() 裸用了实例属性」这种不存在的错（2026-10-07 实测）。
  // 现在参数表里禁止出现括号/花括号，且 `)` 与 `{` 之间不许有 `;`，回溯就跑不远了。
  const re = /static\s+func\s+(\w+)\s*\(([^(){}]*)\)[^{;]*\{/g;
  let m2;
  while ((m2 = re.exec(bare))) {
    const fnName = m2[1];
    const open = m2.index + m2[0].length - 1;
    let d = 0, end = -1;
    for (let i = open; i < bare.length; i++) {
      if (bare[i] === "{") d++;
      else if (bare[i] === "}") { d--; if (d === 0) { end = i; break; } }
    }
    if (end < 0) continue;                                  // 括号不配对就不猜
    const body = bare.slice(open + 1, end);
    const params = new Set([...m2[2].matchAll(/(\w+)\s*:/g)].map((x) => x[1]));
    const locals = new Set([...body.matchAll(/\b(?:var|let)\s+(\w+)/g)].map((x) => x[1]));
    for (const p of propNames) {
      if (params.has(p) || locals.has(p)) continue;
      if (new RegExp("(?<![.\\w])" + p + "(?![\\w:])").test(body)) {
        hits.push(`${fnName}() 裸用了实例属性 ${p} —— 要么提成参数，要么前面加类型/实例限定`);
      }
    }
  }
  return hits;
}

for (const [f, { bare }] of stripped) {
  const rel = relative(ROOT, f).replace(/\\/g, "/");
  if (checkTupleKeyPath(bare)) {
    problems.push(`${rel}: 用了 Array(...enumerated()) + id: \\.offset/\\\\.element —— 指向元组成员的 key path 不受支持；改用 id: \\.self 或让元素 Identifiable`);
  }
  if (checkConcreteViewConstraint(bare)) {
    problems.push(`${rel}: 把 View 泛型钉在具体类型上（如 where T == Color）—— ViewBuilder 闭包产出的是修饰后的 View，通常推不出来`);
  }
  for (const h of checkStaticInstanceUse(bare)) {
    problems.push(`${rel}: static 上下文里 ${h}`);
  }
}

// ---- 自测：新判据必须能对反例报出来，否则就是恒真空转 ----
// 用法：node tools/check_swift.mjs --selftest
if (process.argv.includes("--selftest")) {
  // 自测样本必须走**和真实路径同一条路**：先按 structBody 取体，再交给判据。
  // 之前直接把"含声明行的整段"喂进去，等于测了一条生产中不存在的路径 ——
  // 于是判据本身错位时，样本仍能通过（4 条自测当场翻车，2026-10-07）。
  const bodyOf = (src) => structBody(src, src.indexOf("{") + 1);
  const cases = [
    ["元组 key path（反例）", checkTupleKeyPath("ForEach(Array(items.enumerated()), id: \\.offset) { i, x in }"), true],
    ["元组 key path（干净）", checkTupleKeyPath("ForEach(items.indices, id: \\.self) { i in }"), false],
    ["泛型钉死具体 View（反例）", checkConcreteViewConstraint("extension Foo where Trailing == Color {"), true],
    ["泛型钉死具体 View（干净）", checkConcreteViewConstraint("extension Foo where Trailing == EmptyView {"), false],
    ["static 裸用实例属性（反例）", checkStaticInstanceUse([
      "struct A {",
      "    var kittenCount: Int?",
      "    static func line(stage: Int, matedDate: Int) -> String {",
      "        return \"n = \\(kittenCount ?? 0)\"",
      "    }",
      "}",
    ].join("\n")).length > 0, true],
    ["static 裸用实例属性（干净：提成参数）", checkStaticInstanceUse([
      "struct A {",
      "    var kittenCount: Int?",
      "    static func line(stage: Int, kittenCount: Int?) -> String {",
      "        return \"n = \\(kittenCount ?? 0)\"",
      "    }",
      "}",
    ].join("\n")).length > 0, false],
    ["static 裸用实例属性（干净：有同名局部变量）", checkStaticInstanceUse([
      "struct A {",
      "    var f: String?",
      "    static func line() -> String {",
      "        let f = \"x\"",
      "        return f",
      "    }",
      "}",
    ].join("\n")).length > 0, false],
    // 这一条是回归：签名里带 `throws -> T` 时，旧正则回溯到函数体内的 `)` 收尾，
    // 把整个函数体当成参数表 → 对一个完全正确的函数报「裸用了实例属性」。
    ["static 裸用实例属性（干净：throws -> 签名不许回溯）", checkStaticInstanceUse([
      "final class S {",
      "    let storeFileURL: URL",
      "    private static func encode(_ value: Data) throws -> Data {",
      "        let encoder = JSONEncoder()",
      "        return try encoder.encode(value)",
      "    }",
      "}",
    ].join("\n")).length > 0, false],
    // 反向再验一次：深度过滤不能把「函数体里的局部变量」误当成实例属性。
    // 局部 `base` 与真实实例属性 `base2` 同名时，若属性表混进局部名就会漏报。
    ["static 裸用实例属性（反例：局部量同名也不能漏报）", checkStaticInstanceUse([
      "class S {",
      "    var total: Int = 0",
      "    static func f() -> Int {",
      "        let n = 1",
      "        return total + n",
      "    }",
      "}",
    ].join("\n")).length > 0, true],
    // 成员扫描：函数体里的局部变量**不是**成员。
    // 这是 2026-10-07 的真实误报现场 —— SettingsView 里的 `var names: [UUID: String] = [:]`
    // 被判成"外部传入的属性"，于是整屏报"有 private 属性又有外部属性却没 init"。
    ["成员扫描（反例：函数内局部变量不算成员）", memberDeclarations(bodyOf([
      "struct A {",
      "    private var cached: Int = 0",
      "    var title: String = \"\"",
      "    func f() {",
      "        var names: [String] = []",
      "        names.append(\"x\")",
      "    }",
      "}",
    ].join("\n"))).some((d) => d.name === "names"), false],
    // 成员扫描（正例）：真成员必须都在，且 private / 计算属性分别判对。
    ["成员扫描（正例：成员要收全、private 与计算属性要判对）", (() => {
      const ms = memberDeclarations(bodyOf([
        "struct A {",
        "    private var cached: Int = 0",
        "    var title: String = \"\"",
        "    var rows: [String] { return [] }",
        "    private var maxValue: Double { max(1, 2) }",
        "}",
      ].join("\n")));
      const byName = Object.fromEntries(ms.map((d) => [d.name, d]));
      return Object.keys(byName).length === 4
        && byName.cached.isPrivate === true
        && byName.title.isPrivate === false
        && byName.rows.isComputed === true
        && byName.maxValue.isComputed === true;   // ← 单行计算属性结尾是 `}`，也必须判为计算属性
    })(), true],
    // 声明顺序：计算属性（哪怕类型里有方括号、结尾是 `}`）不能被当成存储属性 ——
    // 混进去会让子序列检查变宽，那是"假通过"，比误报更危险。
    ["声明顺序（反例：计算属性不算存储属性）", storedPropertyOrder(bodyOf([
      "struct A {",
      "    var a: Int = 0",
      "    var filtered: [String] { return [] }",
      "    var b: Int = 0",
      "}",
    ].join("\n"))).join(","), "a,b"],
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
