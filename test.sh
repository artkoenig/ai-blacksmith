#!/usr/bin/env bash
# Every check that runs without a Claude Code session.
# Prints one line per suite. A failure prints "FAIL <suite>: <what>".
set -uo pipefail
cd "$(dirname "$0")"

FAILED=0
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAILED=1; }
ok()   { printf 'ok   %s\n' "$1"; }

# --- manifest and syntax ----------------------------------------------------
# No plugin pins a version on purpose - each is released from the tip of main, so
# the commit is the version. --strict warns about exactly that one thing, and
# every other line it prints is a break.
for d in plugins/*/; do
  d="${d%/}"
  if command -v claude >/dev/null; then
    V="$(claude plugin validate "./$d" --strict 2>&1 \
          | grep '^  > ' | grep -v '^  > version: No version specified')"
    [ -z "$V" ] || fail manifest "claude plugin validate rejected $d:${V}"
  fi
  for f in "$d"/workflows/*.js "$d"/scripts/*.js; do
    [ -f "$f" ] || continue
    node --check "$f" 2>/dev/null || fail syntax "$f"
  done
  for f in "$d"/bin/*; do
    [ -f "$f" ] || continue
    bash -n "$f" 2>/dev/null || fail syntax "$f"
    [ -x "$f" ] || fail permissions "$f is not executable"
  done
  for f in "$d"/scripts/*.js; do
    [ -f "$f" ] || continue
    [ -x "$f" ] || fail permissions "$f is not executable"
  done
done
# The marketplace entry is what a user reads before installing, so it mirrors the
# plugin's own manifest - break: shipping behaviour in a plugin and leaving the
# marketplace describing the version before it.
M="$(node -e '
const fs=require("fs");
const mkt=JSON.parse(fs.readFileSync(".claude-plugin/marketplace.json","utf8"));
for (const p of mkt.plugins) {
  const own=JSON.parse(fs.readFileSync(`plugins/${p.name}/.claude-plugin/plugin.json`,"utf8"));
  for (const k of ["displayName","description","keywords"])
    if (JSON.stringify(p[k])!==JSON.stringify(own[k]))
      console.log(`${p.name}: marketplace ${k} ${JSON.stringify(p[k])} does not mirror plugin.json ${JSON.stringify(own[k])}`);
}' 2>&1)"
[ -z "$M" ] || fail manifest "the marketplace does not mirror the plugin manifests: $M"
# forge's own hooks manifest: the only plugin that ships one, so it stays named.
node -e 'JSON.parse(require("fs").readFileSync("plugins/forge/hooks/hooks.json","utf8"))' 2>/dev/null \
  || fail manifest "hooks/hooks.json is not valid JSON"
[ "$FAILED" = 0 ] && ok "manifest and syntax"

# --- fixture project --------------------------------------------------------
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/.forge"
cat > "$FIX/.forge/config.json" <<'JSON'
{ "commands": { "test": { "command": "bash ./fake.sh", "parser": "jest" } },
  "compaction": { "maxLines": 40, "maxChars": 5000 } }
JSON
cat > "$FIX/fake.sh" <<'JSON'
echo "  ✓ accepts a valid token"
echo "  ✕ rejects an expired token"
echo "     expected 401, received 200"
echo "  ✕ refreshes silently"
echo "     expected a new token"
echo "Tests:       2 failed, 1 passed, 3 total"
exit 1
JSON
export CLAUDE_PROJECT_DIR="$FIX"
BIN="$PWD/plugins/forge/bin"

# --- wrapper contract -------------------------------------------------------
# Two answers only: exit 0 with one line, or exit 1 with every failure and its
# detail. Anything a caller would have to escalate for is a break.
S=0
OUT="$(cd "$FIX" && "$BIN/forge-test")"; RC=$?
# a failing run answers through its exit code - break: report returning 0 on a failure
[ "$RC" = 1 ] || { fail wrappers "a failing forge-test did not exit 1"; S=1; }
# it names every failing test - break: reporting only the first id
printf '%s\n' "$OUT" | grep -q "rejects an expired token" \
  || { fail wrappers "the failure report did not name the first failing test"; S=1; }
printf '%s\n' "$OUT" | grep -q "refreshes silently" \
  || { fail wrappers "the failure report did not name every failing test"; S=1; }
# each in its own block - break: reporting one id whose detail happens to swallow the rest
[ -z "$(printf '%s\n' "$OUT" | grep -A1 -F "expected 401, received 200" | tail -n1)" ] \
  || { fail wrappers "a failure's detail ran into the next failure"; S=1; }
# with the detail of each - break: listing ids without their log lines
printf '%s\n' "$OUT" | grep -q "expected 401" \
  || { fail wrappers "the failure report did not carry the detail of a failure"; S=1; }
printf '%s\n' "$OUT" | grep -q "expected a new token" \
  || { fail wrappers "the failure report did not carry the detail of every failure"; S=1; }
# and counts them first - break: dropping the count line
[ "$(printf '%s\n' "$OUT" | head -1)" = "2 of 3 tests failed" ] \
  || { fail wrappers "the failure report did not open with the count"; S=1; }
# an unknown flag is neither pass nor fail - break: a typo reading as a result
(cd "$FIX" && "$BIN/forge-test" --failing >/dev/null 2>&1); [ $? = 2 ] \
  || { fail wrappers "an unknown flag did not exit 2"; S=1; }
(cd "$FIX" && "$BIN/forge-lint" >/dev/null 2>&1); [ $? = 2 ] \
  || { fail wrappers "an unconfigured command did not exit 2"; S=1; }
UNCONF="$(cd "$FIX" && "$BIN/forge-lint" 2>&1)"
case "$UNCONF" in unconfigured*) ;; *) fail wrappers "an unconfigured command did not say so"; S=1 ;; esac
# An unknown subcommand must fail loudly: a typo that exits 0 reads as success.
(cd "$FIX" && "$BIN/forge-cfg" gett >/dev/null 2>&1); [ $? -ne 0 ] \
  || { fail wrappers "forge-cfg exited 0 on an unknown subcommand"; S=1; }
CFG_ERR="$(cd "$FIX" && "$BIN/forge-cfg" gett 2>&1 >/dev/null)"
case "$CFG_ERR" in usage:\ forge-cfg*) ;; *) fail wrappers "forge-cfg did not print its usage line to stderr"; S=1 ;; esac
(cd "$FIX" && "$BIN/forge-cfg" >/dev/null 2>&1); [ $? -ne 0 ] \
  || { fail wrappers "forge-cfg exited 0 with no subcommand"; S=1; }
[ "$(cd "$FIX" && "$BIN/forge-cfg" exists)" = "yes" ] \
  || { fail wrappers "forge-cfg exists did not answer yes"; S=1; }
[ "$(cd "$FIX" && "$BIN/forge-cfg" get commands.test.parser)" = "jest" ] \
  || { fail wrappers "forge-cfg get did not read a known key"; S=1; }
[ "$(cd "$FIX" && "$BIN/forge-cfg" get no.such.key fallback)" = "fallback" ] \
  || { fail wrappers "forge-cfg get did not fall back on a missing key"; S=1; }

# The passing answer is one line and a 0. It reports the run, not the log: a
# passing run whose output carries "error" or matches failingPattern still
# succeeded. typecheck carries no passingPattern, build fails without naming a
# test.
PASSFIX="$(mktemp -d)"
trap 'rm -rf "$FIX" "$PASSFIX"' EXIT
mkdir -p "$PASSFIX/.forge"
cat > "$PASSFIX/.forge/config.json" <<'JSON'
{ "commands": { "test":      { "command": "bash ./fake.sh", "parser": "generic",
                               "failingPattern": "E[0-9]+", "passingPattern": "^ok ",
                               "runArg": "{pattern}" },
                "typecheck": { "command": "bash ./fake.sh", "parser": "generic" },
                "build":     { "command": "bash ./crash.sh", "parser": "generic" },
                "lint":      { "command": "bash ./many.sh", "parser": "generic",
                               "failingPattern": "^FAIL [^:]+" } } }
JSON
cat > "$PASSFIX/fake.sh" <<'SH'
echo "warn: E42 error recovered, 0 failures"
echo "ok   one"
echo "ok   two"
[ "${1:-}" = "only-one" ] && echo "ok   subset"
exit 0
SH
cat > "$PASSFIX/crash.sh" <<'SH'
echo "the compiler exploded"
exit 3
SH
cat > "$PASSFIX/many.sh" <<'SH'
i=1; while [ "$i" -le 25 ]; do echo "FAIL case$i: boom"; i=$((i + 1)); done
exit 1
SH
cd "$PASSFIX" || exit 1
OUT="$(CLAUDE_PROJECT_DIR="$PASSFIX" "$BIN/forge-test")"; RC=$?
cd "$OLDPWD" || exit 1
# a passing run answers 0 - break: report returning the command's code unmapped
[ "$RC" = 0 ] || { fail wrappers "a passing forge-test did not exit 0"; S=1; }
# in one line, counted - break: widening the passing output, or losing the count
[ "$OUT" = "2/2 tests succeeded" ] \
  || { fail wrappers "a passing forge-test did not answer '2/2 tests succeeded'"; S=1; }
# the count comes from the run, not the log's wording - break: parsing a passing log
printf '%s\n' "$OUT" | grep -qi "fail" \
  && { fail wrappers "a passing run reported failures its log merely mentioned"; S=1; }
# a subset runs the pattern - break: dropping the runArg substitution
[ "$(cd "$PASSFIX" && CLAUDE_PROJECT_DIR="$PASSFIX" "$BIN/forge-test" --run only-one)" = "3/3 tests succeeded" ] \
  || { fail wrappers "--run did not pass the pattern to the command"; S=1; }
# no count available - break: printing a half-empty "x/" line
[ "$(cd "$PASSFIX" && CLAUDE_PROJECT_DIR="$PASSFIX" "$BIN/forge-typecheck")" = "all checks succeeded" ] \
  || { fail wrappers "a passing run without a count did not say so"; S=1; }
# a failure that names no test still shows the log - break: an empty exit 1
cd "$PASSFIX" || exit 1
OUT="$(CLAUDE_PROJECT_DIR="$PASSFIX" "$BIN/forge-build")"; RC=$?
cd "$OLDPWD" || exit 1
[ "$RC" = 1 ] || { fail wrappers "a failing forge-build did not exit 1"; S=1; }
printf '%s\n' "$OUT" | grep -q "the compiler exploded" \
  || { fail wrappers "a failure naming no test did not show the log"; S=1; }
# more failures than the cap says so - break: a silent cap reading as the whole list
CAPPED="$(cd "$PASSFIX" && CLAUDE_PROJECT_DIR="$PASSFIX" "$BIN/forge-lint")"
printf '%s\n' "$CAPPED" | grep -q "^the first 20 failures" \
  || { fail wrappers "a capped failure list did not say it was capped"; S=1; }
[ "$S" = 0 ] && ok "wrapper contract"

# --- hook decisions ---------------------------------------------------------
hook() { echo "$2" | node "plugins/forge/scripts/$1"; }
S=0
hook guard-bash.js '{"tool_input":{"command":"npm test"}}' | grep -q '"allow"' \
  || { fail hooks "guard-bash did not rewrite a bare npm test"; S=1; }
hook guard-bash.js '{"tool_input":{"command":"npm test -- --watch"}}' | grep -q '"deny"' \
  || { fail hooks "guard-bash did not refuse npm test with flags"; S=1; }
[ -z "$(hook guard-bash.js '{"tool_input":{"command":"git status"}}')" ] \
  || { fail hooks "guard-bash did not pass an unrelated command through"; S=1; }
[ -z "$(CLAUDE_PROJECT_DIR=/nonexistent hook guard-bash.js '{"tool_input":{"command":"npm test"}}')" ] \
  || { fail hooks "guard-bash acted in a project without .forge/config.json"; S=1; }
hook guard-checkout.js '{"agent_type":"forge:reviewer","tool_input":{"file_path":"src/a.ts"}}' | grep -q '"deny"' \
  || { fail hooks "guard-checkout let the reviewer write into the checkout"; S=1; }
[ -z "$(hook guard-checkout.js '{"agent_type":"forge:reviewer","tool_input":{"file_path":"/tmp/sandbox/probe.js"}}')" ] \
  || { fail hooks "guard-checkout refused a probe outside the checkout"; S=1; }
[ -z "$(hook guard-checkout.js '{"agent_type":"forge:implementer","tool_input":{"file_path":"src/a.ts"}}')" ] \
  || { fail hooks "guard-checkout acted on an agent other than the reviewer"; S=1; }
[ -z "$(hook compact-output.js '{"tool_response":{"stdout":"one\ntwo","stderr":"","interrupted":false,"isImage":false}}')" ] \
  || { fail hooks "compact-output touched a short result"; S=1; }
sized() { node -e '
  const [n,w]=process.argv.slice(1).map(Number)
  const l=[...Array(n)].map((_,i)=>("line "+i).padEnd(w,"x")).join("\n")
  process.stdout.write(JSON.stringify({tool_use_id:"t",tool_response:{stdout:l,stderr:"boom",interrupted:false,isImage:false}}))
' "$1" "$2" | node plugins/forge/scripts/compact-output.js; }
assert_hint() { node -e '
  let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
    const o=(JSON.parse(s||"{}").hookSpecificOutput||{}).updatedToolOutput||{}
    const bad=[]
    if(!/^… output withheld: \d+ lines, \d+ characters → /.test(o.stdout||"")) bad.push("no withheld hint")
    if(!/\.forge\/last\/bash-/.test(o.stdout||"")) bad.push("no log path")
    if(!/grep -n/.test(o.stdout||"")) bad.push("no cheaper way to read it")
    if(o.stderr!=="boom") bad.push("stderr was touched")
    if(bad.length){console.log(bad.join(", "));process.exit(1)}
  })'; }
# under both ceilings nothing is touched - break: withholding an output an agent can afford,
# which sends it to grep a log it did not need
[ -z "$(sized 30 6)" ] || { fail hooks "compact-output withheld an output inside the budget"; S=1; }
# past maxLines the whole stdout is withheld - break: dropping the line ceiling, which lets a
# thousand-line result into the context
sized 50 6 | assert_hint || { fail hooks "compact-output did not withhold an output past maxLines"; S=1; }
# and past maxChars, whatever the line count - break: dropping the character ceiling, which lets
# few but enormous lines through
sized 30 300 | assert_hint || { fail hooks "compact-output did not withhold an output past maxChars"; S=1; }
[ "$S" = 0 ] && ok "hook decisions"

# --- staleness warning ------------------------------------------------------
# A session whose plugin checkout is behind the marketplace tip is told so. The
# version is the last segment of CLAUDE_PLUGIN_ROOT, which the CLI lays out as
# <cache>/<marketplace>/<plugin>/<version>, and the tip comes from the
# marketplace clone beside that cache.
S=0
SS="$(mktemp -d)"
git init -q "$SS/remote"
: > "$SS/remote/f"
git -C "$SS/remote" add f
git -C "$SS/remote" -c user.email=t@t -c user.name=t commit -qm init
TIP="$(git -C "$SS/remote" rev-parse HEAD)"
mkdir -p "$SS/cfg/plugins/marketplaces"
git clone -q "$SS/remote" "$SS/cfg/plugins/marketplaces/mkt"
mkdir -p "$SS/cfg/plugins/marketplaces/nogit"
start() { # <sha> <marketplace> [plugin root, default the cache layout]
  echo '{}' | env CLAUDE_CONFIG_DIR="$SS/cfg" \
    CLAUDE_PLUGIN_ROOT="${3-$SS/cfg/plugins/cache/$2/forge/$1}" \
    node plugins/forge/scripts/session-start.js
}
# an outdated checkout is named - break: dropping the mismatch branch
start 0000000 mkt | grep -q "outdated forge plugin" \
  || { fail staleness "no warning for a checkout behind the tip"; S=1; }
# it names the update command with the plugin and the marketplace it came from,
# both read off the cache path - break: reading the marketplace off the wrong
# path segment, which is what the pre-cache layout did
start 0000000 mkt | grep -q "forge@mkt" \
  || { fail staleness "the warning did not name the plugin and marketplace to update"; S=1; }
# the current checkout is not warned - break: warning without comparing
start "${TIP:0:7}" mkt | grep -q "outdated forge plugin" \
  && { fail staleness "a session on the tip was warned"; S=1; }
# a development checkout is not under the cache and makes no network call and no
# noise - break: dropping the cache-path gate
start 0000000 mkt "$SS/checkout/plugins/forge" | grep -q "outdated forge plugin" \
  && { fail staleness "a development checkout was warned"; S=1; }
# a pinned version names no commit, so nothing is compared - break: treating any
# version string as a SHA
start 2.1.0 mkt | grep -q "outdated forge plugin" \
  && { fail staleness "a pinned version was compared against a commit"; S=1; }
# no answer, no warning - break: treating an empty tip as a mismatch
start 0000000 nogit | grep -q "outdated forge plugin" \
  && { fail staleness "a missing marketplace clone produced a warning"; S=1; }
# the setup notice survives - break: losing it when the staleness check is added
CLAUDE_PROJECT_DIR=/nonexistent start "${TIP:0:7}" mkt | grep -q '/forge:bootstrap' \
  || { fail staleness "the bootstrap notice was lost"; S=1; }
# a set-up project is handed the plugin's own rules, so an update carries them and
# no second bootstrap is needed - break: writing them into the project instead
CLAUDE_PROJECT_DIR="$FIX" start "${TIP:0:7}" mkt | grep -q 'forge-test' \
  || { fail staleness "the plugin rules were not injected into a set-up project"; S=1; }
# an unconfigured project pays for nothing it cannot act on - break: injecting always
CLAUDE_PROJECT_DIR=/nonexistent start "${TIP:0:7}" mkt | grep -q 'forge-test' \
  && { fail staleness "an unconfigured project was charged for the rules"; S=1; }
rm -rf "$SS"
[ "$S" = 0 ] && ok "staleness warning"

# --- context measurement ----------------------------------------------------
CTX="$(mktemp -d)"
trap 'rm -rf "$FIX" "$PASSFIX" "$CTX"' EXIT
mkdir -p "$CTX/.forge" "$CTX/.claude/agents" "$CTX/.claude/skills/probe" "$CTX/.claude/rules"
printf '{ "version": 1 }\n' > "$CTX/.forge/config.json"
cat > "$CTX/.claude/agents/prober.md" <<'MD'
---
name: prober
skills:
  - forge:probe
  - probe
---
The agent body.
MD
printf '# probe\nA skill body.\n' > "$CTX/.claude/skills/probe/SKILL.md"
printf 'a project rule\n' > "$CTX/.claude/rules/forge.md"
# The layout Claude Code writes: the session transcript, and one file per agent
# beside it. The session file is a decoy here - measuring it is the bug.
mkdir -p "$CTX/t/s1/subagents"
cat > "$CTX/t/s1.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"a session prompt, much longer than the agent's"}}
{"type":"assistant","message":{"usage":{"input_tokens":99999},"content":[{"type":"tool_use"},{"type":"tool_use"}]}}
JSONL
cat > "$CTX/t/s1/subagents/agent-a1.jsonl" <<'JSONL'
{"type":"user","agentId":"a1","message":{"role":"user","content":[{"type":"text","text":"twelve chars"}]}}
{"type":"assistant","agentId":"a1","message":{"usage":{"input_tokens":3,"cache_creation_input_tokens":1000,"cache_read_input_tokens":200},"content":[{"type":"tool_use"}]}}
{"type":"assistant","agentId":"other","message":{"usage":{"input_tokens":99999},"content":[{"type":"tool_use"}]}}
{"type":"assistant","agentId":"a1","message":{"usage":{"input_tokens":5,"cache_read_input_tokens":2000},"content":[{"type":"tool_use"},{"type":"tool_use"}]}}
JSONL

# Every forge agent runs through a workflow, and the Workflow tool files its
# agents one level deeper: subagents/workflows/<runId>/. The hook is handed the
# session's transcript, so it has to find that file.
mkdir -p "$CTX/t/s1/subagents/workflows/wf_x" "$CTX/t/elsewhere"
cat > "$CTX/t/s1/subagents/workflows/wf_x/agent-a3.jsonl" <<'JSONL'
{"type":"user","agentId":"a3","message":{"role":"user","content":[{"type":"text","text":"twelve chars"}]}}
{"type":"assistant","agentId":"a3","message":{"usage":{"input_tokens":7,"cache_creation_input_tokens":700},"content":[{"type":"tool_use"},{"type":"tool_use"}]}}
JSONL
# A build that sends agent_transcript_path is believed over any derivation.
cat > "$CTX/t/elsewhere/agent-a4.jsonl" <<'JSONL'
{"type":"user","agentId":"a4","message":{"role":"user","content":[{"type":"text","text":"twelve chars"}]}}
{"type":"assistant","agentId":"a4","message":{"usage":{"input_tokens":9,"cache_creation_input_tokens":400},"content":[{"type":"tool_use"}]}}
JSONL

S=0
echo '{"cwd":"'"$CTX"'","session_id":"s1","agent_id":"a1","agent_type":"forge:prober"}' \
  | CLAUDE_PROJECT_DIR="$CTX" node plugins/forge/scripts/subagent-start.js >/dev/null
echo '{"cwd":"'"$CTX"'","session_id":"s1","agent_id":"a1","agent_type":"forge:prober","transcript_path":"'"$CTX/t/s1.jsonl"'"}' \
  | CLAUDE_PROJECT_DIR="$CTX" node plugins/forge/scripts/subagent-metrics.js >/dev/null
echo '{"cwd":"'"$CTX"'","session_id":"s1","agent_id":"a2","agent_type":"forge:prober","transcript_path":"'"$CTX/t/s1.jsonl"'"}' \
  | CLAUDE_PROJECT_DIR="$CTX" node plugins/forge/scripts/subagent-metrics.js >/dev/null
echo '{"cwd":"'"$CTX"'","session_id":"s1","agent_id":"a3","agent_type":"workflow-subagent","transcript_path":"'"$CTX/t/s1.jsonl"'"}' \
  | CLAUDE_PROJECT_DIR="$CTX" node plugins/forge/scripts/subagent-metrics.js >/dev/null
echo '{"cwd":"'"$CTX"'","session_id":"s1","agent_id":"a4","agent_type":"workflow-subagent","transcript_path":"'"$CTX/t/s1.jsonl"'","agent_transcript_path":"'"$CTX/t/elsewhere/agent-a4.jsonl"'"}' \
  | CLAUDE_PROJECT_DIR="$CTX" node plugins/forge/scripts/subagent-metrics.js >/dev/null

CTX="$CTX" node -e '
  const fs=require("fs"), path=require("path"), root=process.env.CTX
  const last=(f)=>{const l=fs.readFileSync(path.join(root,".forge",f),"utf8").trim().split("\n");return JSON.parse(l[l.length-1])}
  const bad=(m)=>{console.log(m);process.exit(1)}
  const run=last("context.jsonl")
  const kinds=run.sources.map(s=>s.kind)
  for (const k of ["agent","skill","rules"]) if(!kinds.includes(k)) bad("no "+k+" source recorded")
  if (kinds.filter(k=>k==="skill").length!==1) bad("a skill named twice was counted twice")
  if (run.estTokens!==run.sources.filter(s=>s.loaded).reduce((n,s)=>n+s.estTokens,0)) bad("the estimate does not add up")
  const dump=path.join(root,run.dump)
  if (!fs.existsSync(path.join(dump,"index.json"))) bad("no index.json beside the copies")
  for (const s of run.sources.filter(s=>s.loaded)) if(!fs.existsSync(path.join(dump,s.dump))) bad("no copy of "+s.path)
  const lines=fs.readFileSync(path.join(root,".forge","metrics.jsonl"),"utf8").trim().split("\n").map(JSON.parse)
  const m=lines.find(l=>l.agentId==="a1")
  const unmatched=lines.find(l=>l.agentId==="a2")
  for (const k of ["startTokens","peakTokens","toolCalls","promptTokens"])
    if (unmatched[k]!==null) bad("an agent whose turns are not in the transcript was given the session value for "+k)
  if (m.startTokens!==1203) bad("start tokens: "+m.startTokens)
  if (m.peakTokens!==2005) bad("peak tokens: "+m.peakTokens)
  if (m.toolCalls!==3) bad("tool calls counted another agents turns: "+m.toolCalls)
  if (m.promptTokens!==3) bad("prompt tokens: "+m.promptTokens)
  const wf=lines.find(l=>l.agentId==="a3")
  if (wf.toolCalls!==2||wf.startTokens!==707||wf.peakTokens!==707)
    bad("a workflow-spawned agent was not measured: "+JSON.stringify(wf))
  const told=lines.find(l=>l.agentId==="a4")
  if (told.toolCalls!==1||told.startTokens!==409)
    bad("agent_transcript_path was ignored: "+JSON.stringify(told))
' || { fail context "the start hook or the metrics hook measured wrong"; S=1; }

echo '{"cwd":"/nonexistent","agent_type":"forge:prober"}' | node plugins/forge/scripts/subagent-start.js >/dev/null 2>&1 \
  || { fail context "the start hook failed on a project it cannot write to"; S=1; }
(cd "$CTX" && "$BIN/forge-context") | grep -q "forge:prober" \
  || { fail context "forge-context did not list the run"; S=1; }
(cd "$CTX" && "$BIN/forge-context" --sources latest) | grep -q "unattributed" \
  || { fail context "--sources did not name the unattributed remainder"; S=1; }
(cd "$CTX" && "$BIN/forge-context" --dump latest) | grep -q "SKILL.md" \
  || { fail context "--dump did not list the saved copies"; S=1; }
[ "$S" = 0 ] && ok "context measurement"

# The one rules file has two readers: the SessionStart hook injects it, the
# agent protocol attaches it with @. A rename that misses either is silent.
# break: moving plugins/forge/rules/forge.md without following it
[ -f plugins/forge/rules/forge.md ] || fail rules "plugins/forge/rules/forge.md is gone"
grep -q "rules', 'forge.md'" plugins/forge/scripts/session-start.js \
  || fail rules "the session start hook no longer reads the rules file"
grep -q '^@${CLAUDE_PLUGIN_ROOT}/rules/forge.md$' plugins/forge/skills/agent-protocol/SKILL.md \
  || fail rules "the agent protocol no longer references the rules file"

# --- a stopped run is resumed -----------------------------------------------
# The runtime keeps a stopped run's finished agents for a resume in the same
# session, so a restart pays for them twice. The behaviour is the session's, not
# the script's, so the rule that states it is what is checked.
# break: dropping the resume line from the plugin rules
grep -q 'resumed, never restarted' plugins/forge/rules/forge.md \
  && ok "a stopped run is resumed" \
  || fail resume "the plugin rules no longer require resuming a stopped run"

# --- the interview starts grounded ------------------------------------------
# What the codebase already does is read out of the codebase, never out of the
# user. That analysis is one dispatch of the built-in Explore agent, so the
# skill carries that tool and no search tool of its own: a Grep here would put
# every excerpt into the one context that has to hold the whole issue.
S=0
# break: dropping Agent(Explore) from allowed-tools
grep -q '^allowed-tools:.*Agent(Explore)' plugins/forge/skills/issue/SKILL.md \
  || { fail grounding "the issue skill can no longer dispatch the Explore agent"; S=1; }
# break: handing the skill its own search tools instead of delegating the analysis
grep -q '^allowed-tools:.*\(Grep\|Glob\)' plugins/forge/skills/issue/SKILL.md \
  && { fail grounding "the issue skill searches itself instead of delegating"; S=1; }
# break: removing the grounding step, or moving it after the interview
G="$(grep -n '^## [0-9]\+\. Ground it$' plugins/forge/skills/issue/SKILL.md | cut -d: -f1)"
I="$(grep -n '^## [0-9]\+\. Interview$' plugins/forge/skills/issue/SKILL.md | cut -d: -f1)"
{ [ -n "$G" ] && [ -n "$I" ] && [ "$G" -lt "$I" ]; } \
  || { fail grounding "the issue skill no longer grounds itself before it asks"; S=1; }
[ "$S" = 0 ] && ok "the interview starts grounded"

# --- the run starts on demand -----------------------------------------------
# Writing an issue spends no dispatch. The behaviour lives in prose, so the
# prose is what is checked: a skill that ends by invoking the workflow starts
# work nobody asked for.
S=0
# break: restoring a "## 4. Start the run" step that invokes /forge:work
grep -q '^## [0-9]\+\. Hand it over$' plugins/forge/skills/issue/SKILL.md \
  || { fail handoff "the issue skill no longer hands the run over"; S=1; }
grep -q 'Never invoke `/forge:work` off the back of writing an issue' \
  plugins/forge/skills/issue/SKILL.md \
  || { fail handoff "the issue skill no longer forbids starting the run itself"; S=1; }
# break: a description that promises the run
grep -niq 'starts\? the run' plugins/forge/skills/issue/SKILL.md \
  && { fail handoff "forge:issue still advertises that it starts the run"; S=1; }
[ "$S" = 0 ] && ok "the run starts on demand"

# --- the readme states no behaviour -----------------------------------------
# Behaviour is defined in the skill, agent, workflow and hook that implement it.
# A second copy in the README is maintained by nobody and drifts.
# break: pasting a rule or a tuning number back into plugins/forge/README.md
grep -niqE '[^0-9](8|eight) rounds|200 lines|10000 characters|maxRounds' plugins/forge/README.md \
  && fail readme "the README restates behaviour that lives in the code" \
  || ok "the readme states no behaviour"

# --- output language --------------------------------------------------------
# Two languages, one boundary: the reply follows the user, the artifacts stay
# English. Both halves are prose, so the prose is what is checked. They sit in
# the one rules file, which the session hook injects and the agent protocol
# attaches - a second copy in either reader is maintained by nobody.
S=0
# break: dropping the reply-language line and going English-only again
grep -q "the language the user writes in" plugins/forge/rules/forge.md \
  || { fail language "the rules no longer reply in the user's language"; S=1; }
# break: dropping the English-artifacts rule
grep -q '^- Write English into every file' plugins/forge/rules/forge.md \
  || { fail language "the rules no longer require English in files"; S=1; }
# break: pasting it back into the agent protocol, which already attaches the file
grep -q 'Write English into every file' plugins/forge/skills/agent-protocol/SKILL.md \
  && { fail language "the agent protocol restates a rule it already attaches"; S=1; }
[ "$S" = 0 ] && ok "output language"

# --- brevity is the built-in style ------------------------------------------
# Claude Code carries Concise since v2.1.237. A style shipped here would have to
# set force-for-plugin to apply at all, and that overrides whatever the user
# picked - so the plugin ships none and the README names the built-in one.
# break: adding an output style back to the plugin
[ -e plugins/forge/output-styles ] \
  && fail style "the plugin ships an output style again" \
  || ok "brevity is the built-in style"

# --- committed rules --------------------------------------------------------
# The rules are the only channel that carries project knowledge into an agent.
# Ignored or untracked, every run rediscovers what was already written down.
if git -C . rev-parse --git-dir >/dev/null 2>&1; then
  S=0
  git check-ignore -q .claude/rules/probe.md \
    && { fail rules ".gitignore swallows .claude/rules/"; S=1; }
  for f in .claude/rules/*.md; do
    [ -e "$f" ] || { fail rules "no project rule is checked in"; S=1; break; }
    git ls-files --error-unmatch "$f" >/dev/null 2>&1 || { fail rules "$f is not tracked"; S=1; }
  done
  [ "$S" = 0 ] && ok "committed rules"
fi

# --- area notes -------------------------------------------------------------
# A note only reaches an agent if its front matter parses and its glob still
# matches something. A note that fails either is silent: the agent researches
# the area again and nobody is told why.
if [ -d .claude/rules/areas ]; then
  S=0
  # The budget is the insights skill's own number. Read it there, so raising it
  # in one place raises it everywhere - break: hardcoding a second copy here.
  BUDGET=$(grep -oE 'Under [0-9]+ lines' plugins/forge/skills/insights/SKILL.md | grep -oE '[0-9]+' | head -1)
  [ -n "$BUDGET" ] || { fail areas "the insights skill names no line budget"; S=1; BUDGET=999999; }
  shopt -s globstar nullglob
  for f in .claude/rules/areas/*.md; do
    head -1 "$f" | grep -q '^---$' || { fail areas "$f has no front matter"; S=1; continue; }
    globs=$(awk 'NR>1 && /^---$/{exit} /^[[:space:]]*-[[:space:]]*"/{gsub(/^[^"]*"|"[^"]*$/,""); print}' "$f")
    [ -n "$globs" ] || { fail areas "$f names no paths"; S=1; continue; }
    while read -r g; do
      [ -n "$g" ] || continue
      m=($g)
      [ ${#m[@]} -gt 0 ] || { fail areas "$f globs \"$g\", which matches nothing"; S=1; }
    done <<< "$globs"
    [ "$(wc -l < "$f")" -le "$BUDGET" ] || { fail areas "$f is past the $BUDGET line budget for a note"; S=1; }
    git ls-files --error-unmatch "$f" >/dev/null 2>&1 || { fail areas "$f is not tracked"; S=1; }
  done
  shopt -u globstar nullglob
  [ "$S" = 0 ] && ok "area notes"
fi

# --- workflow control flow --------------------------------------------------
node - <<'JS' || fail workflow "the control flow did not behave as expected"
const fs=require('fs')
const src=fs.readFileSync('plugins/forge/workflows/work.js','utf8').replace('export const meta','const meta')
const run=(a,{verdicts={},conflicts=[]}={})=>{
  const calls=[]
  const prompts={}
  const live={review:0,peak:0}
  const agent=async(prompt,o)=>{
    calls.push(o.label)
    prompts[o.label]=prompt
    if(o.label.startsWith('review')){
      live.review++;live.peak=Math.max(live.peak,live.review)
      await new Promise(r=>setTimeout(r,1))
      live.review--
    }
    const inc=(o.label.split(':')[1]||'').split('/')[1]||'1'
    if(/^(implement|repair)/.test(o.label)) return {status:'implemented',branch:'b',worktree:a.increments?'/wt':'',base:'b0',sha:'c',summary:'s',files:['src/one.js']}
    const q=verdicts[inc]||[]
    return q.shift()??{pass:true,failed:[],merged:!conflicts.includes(inc)}
  }
  const said=[]
  return new Function('agent','phase','log','parallel','args',`return (async () => {${src}})()`)
    (agent,()=>{},m=>said.push(m),t=>Promise.all(t.map(f=>f())),a).then(r=>({r,calls,peak:live.peak,said,prompts}))
}
const st=r=>Object.fromEntries((r.increments||[]).map(i=>[i.increment,i.status]))
const eq=(a,b,m)=>{if(JSON.stringify(a)!==JSON.stringify(b)){console.log(m,JSON.stringify(a));process.exit(1)}}
;(async()=>{
  let {r,calls}=await run('1')
  eq(r.status,'done','uncut issue')
  eq(r.checkout,'current','an uncut run reported the checkout stale')
  eq(calls,['implement:1','review:1:0'],'uncut dispatch order')

  let peak
  ;({r,calls,peak}=await run({issue:'1',increments:[{id:'a',dependsOn:[]},{id:'b',dependsOn:[]}]}))
  eq(calls.slice(0,2),['implement:1/a','implement:1/b'],'independent increments did not run together')
  eq(st(r),{a:'merged',b:'merged'},'independent outcomes')
  eq(peak,2,'independent increments did not review at the same time')
  eq(r.checkout,'stale','a cut run did not report the main checkout stale')

  ;({r,calls}=await run({issue:'1',increments:[{id:'a',dependsOn:[]},{id:'b',dependsOn:['a']}]}))
  eq(calls.indexOf('implement:1/b')>calls.indexOf('review:1/a:0'),true,'a dependent started before its dependency merged')

  ;({r}=await run({issue:'1',increments:[{id:'a',dependsOn:[]},{id:'b',dependsOn:['a']},{id:'c',dependsOn:[]}]},
    {verdicts:{a:[{pass:false,failed:['AC1']},{pass:false,failed:['AC1']}]}}))
  eq(st(r),{a:'stalled',c:'merged',b:'skipped'},'a stall did not skip dependents while siblings merged')

  ;({r}=await run({issue:'1',increments:[{id:'a',dependsOn:[]},{id:'b',dependsOn:[]}]},{conflicts:['b']}))
  eq(st(r),{a:'merged',b:'conflicted'},'a merge conflict was not reported')

  // The run is silent until it ends unless the workflow says what happened, and
  // no agent has SendMessage any more - break: dropping either log call.
  let said
  ;({said}=await run('1'))
  eq(said,['1: s','1: passed, landed'],'a clean run told the user nothing')
  const rejected={pass:false,failed:['AC1'],
    findings:[{id:'AC1',evidence:'still red',sites:['src/one.js:12','src/two.js']}]}
  ;({said}=await run('1',{verdicts:{1:[rejected]}}))
  eq(said,['1: s','1: rejected - AC1 - AC1: still red','1: repair 1 - s','1: passed, landed'],
    'a rejection and its repair did not reach the user')

  // The reviewer hands the repair the sites it already found, so the round does not
  // re-locate them - break: passing `verdict.notes` to the repair prompt again, or
  // dropping the `sites` line from it.
  let prompts
  ;({prompts}=await run('1',{verdicts:{1:[rejected]}}))
  const rp=prompts['repair:1:1']
  for(const want of ['AC1','still red','src/one.js:12','src/two.js'])
    eq(rp.includes(want),true,`the repair prompt dropped ${want} -`)

  // The repair starts at its own diff - break: dropping the diff instruction, or the
  // base and sha it names.
  eq(/git diff b0\.\.c/.test(rp),true,'the repair prompt did not name the round diff -')
  eq(rp.includes('src/one.js'),true,'the repair prompt did not name the files the round touched -')

  // Nothing reads `verdict.notes` any more - break: reinstating any consumer of it.
  eq(/verdict\.notes|\.notes\b/.test(src),false,'a consumer of verdict.notes survives -')

  // A criterion of the increment can never be preexisting: an unmet criterion is red at
  // the base by definition, so "proven at the base" would pass every criterion nobody
  // implemented. Case: one criterion over two sites, only one of them fixed - break:
  // dropping the misfiled-criterion check before `if (verdict.pass)`.
  ;({r,said,calls,prompts}=await run('1',{verdicts:{1:[
    {pass:true,failed:[],preexisting:['AC2: the grep over src/one.js and src/two.js is still red, red at the base too']},
  ]}}))
  eq(said[1],'1: rejected - AC2 - AC2: filed as preexisting - a criterion of this increment is red at the base '
    +'by definition, so that is not a reason to pass it: AC2: the grep over src/one.js and src/two.js is still red, '
    +'red at the base too','a criterion filed as preexisting was not rejected -')
  eq(calls,['implement:1','review:1:0','repair:1:1','review:1:1'],'a misfiled criterion did not cost a repair round')
  eq(prompts['repair:1:1'].includes('Fix only these criteria: AC2.'),true,'the repair was not pointed at the criterion -')
  eq(r.status,'done','the run did not recover after the repair')
  eq(r.increments[0].preexisting,[],'the misfiled criterion stayed in preexisting -')

  // A collateral check red at the base is still preexisting and still blocks nothing -
  // break: rejecting on any non-empty `preexisting` instead of on a criterion in it.
  ;({r,calls}=await run('1',{verdicts:{1:[
    {pass:true,failed:[],preexisting:['forge-test: the lint suite is red at the base too']},
  ]}}))
  eq(calls,['implement:1','review:1:0'],'a collateral preexisting failure cost a repair round')
  eq(r.increments[0].preexisting,['forge-test: the lint suite is red at the base too'],
    'a collateral preexisting failure was not reported')

  // Only the increment's own criteria count. A cut increment that does not own AC9 must
  // still be able to report it red at the base - break: matching /AC\d+/ without the
  // increment's criteria list.
  ;({r,calls}=await run({issue:'1',increments:[{id:'a',criteria:['AC1'],dependsOn:[]}]},{verdicts:{1:[
    {pass:true,failed:[],preexisting:['AC9 of the other increment is red at the base']},
  ]}}))
  eq(calls,['implement:1','review:1:0'],"another increment's criterion was treated as this one's")

  eq((await run('')).r.status,'error','a missing issue id was accepted')
  eq((await run({issue:'1',agentPrefix:''})).r.status,'done','agentPrefix did not resolve')
})()
JS
[ "$FAILED" = 0 ] && ok "workflow control flow"

# --- cast: the module graph -------------------------------------------------
# One fixture project, scanned once, six suites reading the one graph. It carries
# a relative import, an alias import of the same module, a require, an export
# from, a dynamic import, a statement type import, an external package, a broken
# relative import, a broken alias, an a->b->c->a cycle, and two modules of a
# language the engine has never heard of, described by an adapter the fixture
# itself ships.
CASTFIX="$(mktemp -d)"
CASTIDS="$(mktemp -d)"
CMTFIX="$(mktemp -d)"
trap 'rm -rf "$FIX" "$PASSFIX" "$CTX" "$CASTFIX" "$CASTIDS" "$CMTFIX"' EXIT
mkdir -p "$CASTFIX/src" "$CASTFIX/pkg" "$CASTFIX/.cast/adapters" "$CASTFIX/node_modules/react"
cat > "$CASTFIX/tsconfig.json" <<'JSON'
{ "compilerOptions": { "baseUrl": ".", "paths": { "@app/*": ["src/*"] } } }
JSON
cat > "$CASTFIX/src/a.ts" <<'TS'
import { b } from './b'
import type { T } from '@app/t'
import React from 'react'
import './missing-file'
import { g } from '@app/gone'
export async function load() { return import('./c') }
TS
cat > "$CASTFIX/src/b.ts" <<'TS'
const { c } = require('./c')
module.exports = { c }
const lib = require(path.join(__dirname, 'lib.js'))
const load = (n) => import(BASE + n)
const tag = `${require('react')}`
TS
printf "export { load } from './a'\n" > "$CASTFIX/src/c.ts"
printf 'export type T = string\n' > "$CASTFIX/src/t.ts"
printf "import type { T } from './t'\nexport type U = T\n" > "$CASTFIX/src/rel.ts"
cat > "$CASTFIX/src/multi.ts" <<'TS'
import {
  T,
} from './t'
TS
cat > "$CASTFIX/.cast/adapters/toy.js" <<'JS'
'use strict'
const p = require('path').posix
module.exports = {
  name: 'toy', extensions: ['.toy'], patterns: [{ kind: 'value', re: /use\s+"([^"]+)"/g }],
  resolve(s, from, ctx) { const t = p.join(p.dirname(from), s + '.toy'); return ctx.isFile(t) ? { to: t } : null },
}
JS
# The toy adapter says nothing about comments, so its text is matched whole: a
# `//` is no comment in a language that never said it was one.
printf '// in toy this is no comment: use "two"\n' > "$CASTFIX/pkg/one.toy"
printf 'nothing here\n' > "$CASTFIX/pkg/two.toy"
# The layers the fixture is read at: one module in its own layer, the rest of src
# below it, and pkg claimed by no glob at all.
cat > "$CASTFIX/.cast/layers.json" <<'JSON'
{ "src/a.ts": "ui", "src/**": "logic" }
JSON

CAST_BIN="$PWD/plugins/cast/bin/cast"
S=0
CAST_SCAN="$(cd "$CASTFIX" && "$CAST_BIN" scan 2>&1)" \
  || { fail "cast graph" "cast scan did not run: $CAST_SCAN"; S=1; }
# The graph is written outside the checkout, so the line the scan printed is the
# only thing that knows where it is. Every suite below reads it through here.
CAST_GRAPH_FILE="$(printf '%s\n' "$CAST_SCAN" | sed -n 's/^[0-9]* modules scanned into //p')"
CAST_REPORT="$(cd "$CASTFIX" && "$CAST_BIN" report 2>&1)"
# Assert against the written graph, never against an in-process call: the file is
# the contract, and a scan that computes the right answer without writing it is a
# scan nothing downstream can read.
graph() { CAST_GRAPH_FILE="$CAST_GRAPH_FILE" node -e '
  const bad=(s)=>{console.log(s);process.exit(1)}
  let g
  try { g=JSON.parse(require("fs").readFileSync(process.env.CAST_GRAPH_FILE,"utf8")) }
  catch(e) { bad("no readable graph at "+process.env.CAST_GRAPH_FILE+": "+e.message) }
  const mod=(id)=>g.modules.find(x=>x.id===id)
  const edge=(id,t)=>((mod(id)||{}).edges||[]).find(x=>x.target===t)
  '"$1"'
'; }

# AC1 one entry per source module with its outgoing edges, driven by an adapter
# break: dropping a module from the walk, or the edges from an entry
O="$(graph '
  for (const id of ["src/a.ts","src/b.ts","src/c.ts","src/t.ts","src/rel.ts","src/multi.ts"])
    if (!mod(id)) bad("no entry for the source module "+id)
  if (!(mod("src/a.ts").edges||[]).length) bad("a module with imports carries no outgoing edges")
  if (mod("src/t.ts").edges.length) bad("a module with no imports was given edges")
  if (mod("tsconfig.json")) bad("a file no adapter claims was scanned as a module")
')" || { fail "cast graph" "$O"; S=1; }
# the language knowledge is the adapter file, not the engine
# break: hardcoding the javascript extensions, patterns or resolver into cast.js,
# which leaves a project-supplied adapter with nothing to drive
O="$(graph '
  if (!mod("pkg/one.toy")) bad("a project adapter did not put its own modules in the graph")
  const e=edge("pkg/one.toy","two")
  // AC5 the toy adapter declares no comments, so the whole text is matched
  // break: masking every adapter with the javascript comment syntax, which eats
  // this line and with it the only edge the project adapter has
  if (!e) bad("a project adapter pattern produced no edge")
  if (e.to!=="pkg/two.toy") bad("a project adapter resolver was not used: "+e.to)
')" || { fail "cast graph" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast graph"

# --- cast graph location ----------------------------------------------------
# The graph is derived state and stays out of the tree it describes. A scan that
# writes it into the checkout is one every project has to gitignore and every
# agent leaves a file behind for.
S=0
# break: writing <root>/.cast/graph.json again - the fixture is scanned by every
# suite above, so a graph in the checkout would be sitting there now
[ -e "$CASTFIX/.cast/graph.json" ] \
  && { fail "cast graph location" "the scan wrote the graph into the checkout"; S=1; }
find "$CASTFIX" -name 'graph.json' | grep -q . \
  && { fail "cast graph location" "the scan left a graph.json somewhere in the checkout"; S=1; }
# break: printing the path relative to a root the file is no longer under, which
# reads as ../../tmp/... and names nothing the caller can open
case "$CAST_GRAPH_FILE" in
  /*) [ -f "$CAST_GRAPH_FILE" ] \
        || { fail "cast graph location" "the path the scan printed is not a readable file: $CAST_GRAPH_FILE"; S=1; } ;;
  *) fail "cast graph location" "cast scan printed no absolute path: $CAST_SCAN"; S=1 ;;
esac
# break: keying the file on the working directory instead of the root, so a scan
# and the report reading it back disagree the moment they run from different
# places - which is every agent, and cast-check
CAST_ELSEWHERE="$(cd / && "$CAST_BIN" report --root "$CASTFIX" 2>&1)"
printf '%s\n' "$CAST_ELSEWHERE" | grep -q '^modules ' \
  || { fail "cast graph location" "a report from another directory did not find the graph: $CAST_ELSEWHERE"; S=1; }
# break: one file for every root, so scanning a subdirectory overwrites the
# graph of the project it sits in - the whole reason a root can be a subtree
CAST_SUB="$(cd "$CASTFIX" && "$CAST_BIN" scan --root src 2>&1)"
CAST_SUBFILE="$(printf '%s\n' "$CAST_SUB" | sed -n 's/^[0-9]* modules scanned into //p')"
[ "$CAST_SUBFILE" = "$CAST_GRAPH_FILE" ] \
  && { fail "cast graph location" "two roots were scanned into the same file"; S=1; }
CAST_WHOLE="$(printf '%s\n' "$CAST_REPORT" | awk '/^modules /{print $2; exit}')"
printf '%s\n' "$(cd "$CASTFIX" && "$CAST_BIN" report 2>&1)" | grep -qx "modules $CAST_WHOLE" \
  || { fail "cast graph location" "scanning a subdirectory overwrote the graph of the project"; S=1; }
# break: ignoring CAST_GRAPH, which leaves an agent handed a scratch directory
# writing into the shared one anyway
CAST_NAMED="$CASTIDS/named-graph.json"
CAST_NS="$(cd "$CASTFIX" && CAST_GRAPH="$CAST_NAMED" "$CAST_BIN" scan 2>&1)"
[ -f "$CAST_NAMED" ] \
  || { fail "cast graph location" "CAST_GRAPH did not name the file the scan wrote: $CAST_NS"; S=1; }
printf '%s\n' "$CAST_NS" | grep -qF "$CAST_NAMED" \
  || { fail "cast graph location" "the scan did not print the file CAST_GRAPH named: $CAST_NS"; S=1; }
rm -f "$CAST_GRAPH_FILE"
CAST_NR="$(cd "$CASTFIX" && CAST_GRAPH="$CAST_NAMED" "$CAST_BIN" report 2>&1)"
printf '%s\n' "$CAST_NR" | grep -q '^modules ' \
  || { fail "cast graph location" "a report did not read the graph CAST_GRAPH names: $CAST_NR"; S=1; }
# and the readers say where they looked when there is nothing there
CAST_NG="$(cd "$CASTFIX" && "$CAST_BIN" report 2>&1)"; RC=$?
[ "$RC" = 2 ] \
  || { fail "cast graph location" "a report with no graph exited $RC, not 2: $CAST_NG"; S=1; }
printf '%s\n' "$CAST_NG" | grep -qF "$CAST_GRAPH_FILE" \
  || { fail "cast graph location" "the missing graph was not named: $CAST_NG"; S=1; }
(cd "$CASTFIX" && "$CAST_BIN" scan >/dev/null 2>&1) \
  || { fail "cast graph location" "the fixture could not be rescanned"; S=1; }
# break: dropping the root check, so a directory that is not there throws out of
# the walk instead of saying which one was asked for
CAST_NOROOT="$("$CAST_BIN" scan --root "$CASTFIX/nowhere" 2>&1)"; RC=$?
[ "$RC" = 2 ] \
  || { fail "cast graph location" "a root that is no directory exited $RC, not 2: $CAST_NOROOT"; S=1; }
printf '%s\n' "$CAST_NOROOT" | grep -qF "$CASTFIX/nowhere" \
  || { fail "cast graph location" "the root that is no directory was not named: $CAST_NOROOT"; S=1; }
[ "$S" = 0 ] && ok "cast graph location"

# AC2 every edge carries its kind
S=0
# break: dropping the type pattern, which reclassifies `import type` as value
O="$(graph '
  const want={"src/a.ts":{"./b":"value","@app/t":"type","react":"value","./c":"dynamic"},
              "src/b.ts":{"./c":"value"},"src/c.ts":{"./a":"value"},"src/rel.ts":{"./t":"type"}}
  for (const [id,edges] of Object.entries(want))
    for (const [t,k] of Object.entries(edges)) {
      const e=edge(id,t)
      if (!e) bad("no edge for "+t+" in "+id)
      if (e.kind!==k) bad(id+" -> "+t+" is "+e.kind+", not "+k)
    }
  for (const m of g.modules) for (const e of m.edges)
    if (!["value","type","dynamic"].includes(e.kind)) bad("an edge carries no kind: "+JSON.stringify(e))
')" || { fail "cast edge kinds" "$O"; S=1; }
# AC4 a require inside a template literal's ${} is code, and keeps its edge
# break: blanking string literals along with the comments - the specifier lives
# in one, and a template literal is where that is easiest to get wrong
O="$(graph '
  const e=edge("src/b.ts","react")
  if (!e) bad("a require inside a template literal produced no edge")
  if (e.kind!=="value") bad("a require inside a template literal is "+e.kind+", not value")
')" || { fail "cast edge kinds" "$O"; S=1; }
# the opaque imports keep their kinds too - break: dropping the kind from an
# opaque edge, which leaves half the graph unclassified
O="$(graph '
  const op=(mod("src/b.ts").edges||[]).filter(x=>x.resolution==="opaque")
  const kinds=op.map(x=>x.kind).sort().join(",")
  if (kinds!=="dynamic,value") bad("the opaque edges carry the kinds "+kinds+", not dynamic,value")
')" || { fail "cast edge kinds" "$O"; S=1; }
# the same import counted once, not once per pattern that matches its text
# break: dropping the (line, specifier) dedupe
O="$(graph '
  const seen=new Set()
  for (const m of g.modules) for (const e of m.edges) {
    const k=e.file+":"+e.line+" "+e.target
    if (seen.has(k)) bad("one import produced two edges: "+k)
    seen.add(k)
  }
')" || { fail "cast edge kinds" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast edge kinds"

# --- cast comments ----------------------------------------------------------
# An import written in a comment is no import. Its own fixture: the shared one is
# read by a dozen suites on fixed counts, and a comment case belongs where it can
# be read next to what it asserts.
S=0
mkdir -p "$CMTFIX/src"
# Every mention of another module here is an annotation or a commented-out line.
cat > "$CMTFIX/src/annotated.ts" <<'TS'
/** @type {import('./b').B} */
/**
 * @param {import('./c').C} c
 * @returns {import('./d').D}
 * @typedef {import('./e').E} E
 */
export function f(c) { return c }
// import('./g')
// import { h } from './h'
/* require('./i') */
export const z = `${/* import('./j') */ 1}`
TS
# A `//` or a `/*` inside a string literal opens no comment.
cat > "$CMTFIX/src/strings.ts" <<'TS'
const u = 'http://example.com'; import('./dyn')
const g = '/* not a comment'; const r = require('./req')
const s = "// not a comment"; import { v } from './val'
const t = `${require('./tpl')}`
export { u, g, s, t, r, v }
TS
# A regex literal is no string: a quote inside its character class opens nothing,
# and a `/` that divides opens no literal.
cat > "$CMTFIX/src/regex.ts" <<'TS'
const re = /[^'"\s)]/g
// import('./gone')
/** @type {import('./vanished').V} */
const slash = /\/\//
const half = 6 / 2; import('./after'); const t = half / 1
const r = require('./req')
export { re, slash, half, t, r }
TS
# A block comment spans lines: what follows it is reported where it is written.
cat > "$CMTFIX/src/lines.ts" <<'TS'
/*
 * import('./skip')
 */
import { k } from './keep'
TS
CMT_SCAN="$(cd "$CMTFIX" && "$CAST_BIN" scan 2>&1)" \
  || { fail "cast comments" "cast scan did not run: $CMT_SCAN"; S=1; }
CMT_FILE="$(printf '%s\n' "$CMT_SCAN" | sed -n 's/^[0-9]* modules scanned into //p')"
cgraph() { CAST_GRAPH_FILE="$CMT_FILE" node -e '
  const bad=(s)=>{console.log(s);process.exit(1)}
  let g
  try { g=JSON.parse(require("fs").readFileSync(process.env.CAST_GRAPH_FILE,"utf8")) }
  catch(e) { bad("no readable graph at "+process.env.CAST_GRAPH_FILE+": "+e.message) }
  const mod=(id)=>g.modules.find(x=>x.id===id)
  const edge=(id,t)=>((mod(id)||{}).edges||[]).find(x=>x.target===t)
  '"$1"'
'; }
# AC1 a jsdoc annotation naming a module is no import
# AC2 a commented-out import is no import, line comment and block comment alike
# break: matching the patterns over the raw text, which reads every annotation
# and every commented-out line as an edge; and, for the one inside a `${}`,
# reading a template literal as one run of string that never returns to code
O="$(cgraph '
  const m=mod("src/annotated.ts")
  if (!m) bad("the annotated module was not scanned")
  if (m.edges.length)
    bad("a comment produced edges: "+m.edges.map(e=>e.target+":"+e.line).join(", "))
')" || { fail "cast comments" "$O"; S=1; }
# AC3 a comment token inside a string literal opens no comment
# break: blanking comments without reading string literals, which lets the `//`
# of a url or the `/*` of a string swallow the code after it
O="$(cgraph '
  const want={"./dyn":"dynamic","./req":"value","./val":"value","./tpl":"value"}
  for (const [t,k] of Object.entries(want)) {
    const e=edge("src/strings.ts",t)
    if (!e) bad("an import after a comment token in a string produced no edge: "+t)
    if (e.kind!==k) bad(t+" is "+e.kind+", not "+k)
  }
')" || { fail "cast comments" "$O"; S=1; }
# AC1/AC2 a quote inside a regex literal opens no string, so a jsdoc annotation
# and a commented-out import after one are still comments
# break: dropping the regex-literal span from mask(), which enters string state
# at the quote in the character class and leaves nothing after it blanked
O="$(cgraph '
  for (const t of ["./gone","./vanished"]) {
    const e=edge("src/regex.ts",t)
    if (e) bad("a comment after a regex literal produced the edge "+t+":"+e.line)
  }
')" || { fail "cast comments" "$O"; S=1; }
# a `/` that divides opens no literal, and the code between two of them is code
# break: opening a regex literal on any `/`, which swallows the import after it
O="$(cgraph '
  const a=edge("src/regex.ts","./after")
  if (!a) bad("the import after a division produced no edge")
  if (a.line!==5) bad("the import after a division is reported at line "+a.line+", not 5")
  const r=edge("src/regex.ts","./req")
  if (!r) bad("the require after a regex literal produced no edge")
')" || { fail "cast comments" "$O"; S=1; }
# the line an import is reported at does not move
# break: deleting the comments instead of blanking them, which shifts every line
# after a block comment
O="$(cgraph '
  if (edge("src/lines.ts","./skip")) bad("an import inside a block comment made an edge")
  const e=edge("src/lines.ts","./keep")
  if (!e) bad("the import after a block comment produced no edge")
  if (e.line!==4) bad("the import after a block comment is reported at line "+e.line+", not 4")
')" || { fail "cast comments" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast comments"

# AC3 every edge carries the file and the line of its import
S=0
# break: dropping file or line from the edge, or counting lines from the wrong end
O="$(graph '
  const at={"./b":1,"@app/t":2,"react":3,"./missing-file":4,"@app/gone":5,"./c":6}
  for (const [t,line] of Object.entries(at)) {
    const e=edge("src/a.ts",t)
    if (!e) bad("no edge for "+t)
    if (e.file!=="src/a.ts") bad(t+" names the file "+e.file)
    if (e.line!==line) bad(t+" is at line "+e.line+", not "+line)
  }
  for (const m of g.modules) for (const e of m.edges) {
    if (e.file!==m.id) bad("an edge of "+m.id+" names the file "+e.file)
    if (!Number.isInteger(e.line)||e.line<1) bad("an edge of "+m.id+" carries no line")
  }
')" || { fail "cast edge sites" "$O"; S=1; }
# an import spread over several lines is reported where it starts
# break: taking the offset of the specifier instead of the start of the statement
O="$(graph '
  const e=edge("src/multi.ts","./t")
  if (!e) bad("a multi-line import produced no edge")
  if (e.line!==1) bad("a multi-line import is reported at line "+e.line+", not where it starts")
')" || { fail "cast edge sites" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast edge sites"

# AC4 an alias import lands on the node the relative import lands on
S=0
# break: dropping the tsconfig paths lookup, which makes @app/t external or unresolved
O="$(graph '
  const a=edge("src/a.ts","@app/t"), r=edge("src/rel.ts","./t")
  if (!a) bad("an alias import produced no edge")
  if (a.resolution!=="module") bad("an alias import resolved to "+a.resolution)
  if (a.to!==r.to) bad("the alias landed on "+a.to+", the relative import on "+r.to)
  if (a.to!=="src/t.ts") bad("the alias landed on "+a.to)
')" || { fail "cast alias" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast alias"

# AC5 an import that resolves to nothing is counted and named, never dropped
S=0
# break: dropping the edge when resolve answers nothing
O="$(graph '
  for (const t of ["./missing-file","@app/gone"]) {
    const e=edge("src/a.ts",t)
    if (!e) bad("an unresolvable import was dropped from the graph: "+t)
    if (e.resolution!=="unresolved") bad(t+" was filed as "+e.resolution)
  }
  const ext=edge("src/a.ts","react")
  if (ext.resolution!=="external") bad("an installed package was filed as "+ext.resolution)
')" || { fail "cast unresolved" "$O"; S=1; }
# break: reporting a count without the sites, which names nothing to go and fix
printf '%s\n' "$CAST_REPORT" | grep -q '^unresolved 2$' \
  || { fail "cast unresolved" "cast report did not count the unresolved imports: $CAST_REPORT"; S=1; }
printf '%s\n' "$CAST_REPORT" | grep -q 'src/a.ts:4 \./missing-file' \
  || { fail "cast unresolved" "cast report did not name an unresolved import"; S=1; }
printf '%s\n' "$CAST_REPORT" | grep -q 'src/a.ts:5 @app/gone' \
  || { fail "cast unresolved" "cast report did not name every unresolved import"; S=1; }
[ "$S" = 0 ] && ok "cast unresolved"

# AC1 an import or require whose target is not a literal string is counted and
# named, so a graph that is missing edges says so instead of reading as complete
S=0
# break: passing the line over because no pattern reads a computed specifier,
# which drops the edge and leaves nothing in the report to say it was dropped
O="$(graph '
  const op=(mod("src/b.ts").edges||[]).filter(x=>x.resolution==="opaque")
  if (op.length!==2) bad("the computed imports of src/b.ts made "+op.length+" opaque edges")
  if (op.some(x=>x.to!==null)) bad("an opaque import was given a target module")
  if (!op.some(x=>x.target.indexOf("path.join")!==-1))
    bad("an opaque edge does not carry the expression: "+JSON.stringify(op))
  const lit=edge("src/b.ts","./c")
  if (!lit||lit.resolution!=="module") bad("a literal require was filed as "+(lit&&lit.resolution))
  if (!edge("pkg/one.toy","two")) bad("an adapter that declares no opaque patterns lost its edges")
')" || { fail "cast opaque imports" "$O"; S=1; }
# break: counting them into unresolved, where a site nobody can resolve reads as
# an import that was looked up and missed
printf '%s\n' "$CAST_REPORT" | grep -q '^opaque 2$' \
  || { fail "cast opaque imports" "cast report did not count the opaque imports: $CAST_REPORT"; S=1; }
printf '%s\n' "$CAST_REPORT" | grep -q '^unresolved 2$' \
  || { fail "cast opaque imports" "an opaque import was counted as unresolved: $CAST_REPORT"; S=1; }
# break: a count without the sites, which names nothing to go and look at
printf '%s\n' "$CAST_REPORT" | grep -qF "  src/b.ts:3 path.join(__dirname, 'lib.js') (value)" \
  || { fail "cast opaque imports" "cast report did not name the computed require: $CAST_REPORT"; S=1; }
printf '%s\n' "$CAST_REPORT" | grep -qF "  src/b.ts:4 BASE + n (dynamic)" \
  || { fail "cast opaque imports" "cast report did not name the computed import: $CAST_REPORT"; S=1; }
[ "$S" = 0 ] && ok "cast opaque imports"

# AC6 a cycle is named by all of its modules
S=0
# break: reporting the module the walk entered the cycle through instead of the
# whole strongly connected component
printf '%s\n' "$CAST_REPORT" | grep -q '^cycles 1$' \
  || { fail "cast cycles" "cast report did not count the cycle: $CAST_REPORT"; S=1; }
printf '%s\n' "$CAST_REPORT" | grep '^  cycle:' \
  | grep -q 'src/a\.ts.*src/b\.ts.*src/c\.ts' \
  || { fail "cast cycles" "cast report did not name every module of the cycle: $CAST_REPORT"; S=1; }
# a module outside the cycle is not swept into it - break: reporting every
# reachable module rather than the component
printf '%s\n' "$CAST_REPORT" | grep '^  cycle:' | grep -q 'src/t\.ts' \
  && { fail "cast cycles" "a module outside the cycle was named in it"; S=1; }
[ "$S" = 0 ] && ok "cast cycles"

# AC1 layers.json maps globs to layer names and every module lands in exactly one
S=0
# break: dropping the layers section from the report, or placing a module in
# every layer whose glob matches it instead of the first
printf '%s\n' "$CAST_REPORT" | grep -q '^layers 2$' \
  || { fail "cast layers" "cast report did not count the layers: $CAST_REPORT"; S=1; }
printf '%s\n' "$CAST_REPORT" | grep -q '^  ui 1$' \
  || { fail "cast layers" "cast report did not size the ui layer: $CAST_REPORT"; S=1; }
printf '%s\n' "$CAST_REPORT" | grep -q '^  logic 5$' \
  || { fail "cast layers" "cast report did not size the logic layer: $CAST_REPORT"; S=1; }
# exactly one: the layer counts and the unassigned count add up to the modules,
# so a module placed twice or dropped shows here
# break: letting a later glob place a module a earlier one already claimed
SUM="$(printf '%s\n' "$CAST_REPORT" | awk '
  /^layers /{inl=1;next} /^unassigned /{n+=$2;inl=0;next}
  inl&&/^  /{n+=$2;next} {inl=0} END{print n+0}')"
MODS="$(printf '%s\n' "$CAST_REPORT" | awk '/^modules /{print $2}')"
[ "$SUM" = "$MODS" ] \
  || { fail "cast layers" "$MODS modules were placed $SUM times: $CAST_REPORT"; S=1; }
[ "$S" = 0 ] && ok "cast layers"

# a layers.json that is present but unreadable stops the run: the directory-level
# fallback answers for a missing file only
S=0
CAST_LAYERS="$CASTFIX/.cast/layers.json"
cp "$CAST_LAYERS" "$CASTFIX/layers.bak"
printf '{ "src/a.ts": ' > "$CAST_LAYERS"
CAST_LM="$(cd "$CASTFIX" && "$CAST_BIN" report 2>&1)"; RC=$?
# break: catching the parse the way the missing file is caught, which reads the
# graph at an altitude nobody declared and never says the layer file was ignored
[ "$RC" = 2 ] \
  || { fail "cast layers malformed" "a malformed layers.json exited $RC, not 2: $CAST_LM"; S=1; }
printf '%s\n' "$CAST_LM" | grep -q 'layers.json is not valid JSON' \
  || { fail "cast layers malformed" "the malformed layer file was not named: $CAST_LM"; S=1; }
printf '%s\n' "$CAST_LM" | grep -q '^layers ' \
  && { fail "cast layers malformed" "the run fell back to directory layering: $CAST_LM"; S=1; }
# a file that cannot be read at all is the same answer, not a fallback either
rm -f "$CAST_LAYERS"; mkdir "$CAST_LAYERS"
CAST_LU="$(cd "$CASTFIX" && "$CAST_BIN" report 2>&1)"; RC=$?
# break: one bare catch around read and parse together, which swallows this too
[ "$RC" = 2 ] \
  || { fail "cast layers malformed" "an unreadable layers.json exited $RC, not 2: $CAST_LU"; S=1; }
printf '%s\n' "$CAST_LU" | grep -q 'layers.json could not be read' \
  || { fail "cast layers malformed" "the unreadable layer file was not named: $CAST_LU"; S=1; }
rmdir "$CAST_LAYERS"
# no layers.json at all is still the documented default, not an error
# break: turning the missing file into an exit 2, which makes a first run need a
# layer file before it can say anything
CAST_LN="$(cd "$CASTFIX" && "$CAST_BIN" report 2>&1)"; RC=$?
[ "$RC" = 0 ] || { fail "cast layers malformed" "no layers.json exited $RC, not 0: $CAST_LN"; S=1; }
printf '%s\n' "$CAST_LN" | grep -q '^layers ' \
  || { fail "cast layers malformed" "the directory-level fallback did not run: $CAST_LN"; S=1; }
cp "$CASTFIX/layers.bak" "$CAST_LAYERS"; rm -f "$CASTFIX/layers.bak"
[ "$S" = 0 ] && ok "cast layers malformed"

# AC2 a layers.json whose values are not layer names stops the run
S=0
cp "$CAST_LAYERS" "$CASTFIX/layers.bak"
printf '{ "src/**": { "name": "logic" } }\n' > "$CAST_LAYERS"
CAST_LSH="$(cd "$CASTFIX" && "$CAST_BIN" report 2>&1)"; RC=$?
# break: String(name) on the value, which invents a layer named [object Object]
# and reads the whole graph at an altitude nobody declared
[ "$RC" = 2 ] \
  || { fail "cast layers shape" "a layers.json of non-names exited $RC, not 2: $CAST_LSH"; S=1; }
printf '%s\n' "$CAST_LSH" | grep -q 'not a layer name' \
  || { fail "cast layers shape" "the message did not say what was expected: $CAST_LSH"; S=1; }
printf '%s\n' "$CAST_LSH" | grep -qF 'src/**' \
  || { fail "cast layers shape" "the glob whose value is wrong was not named: $CAST_LSH"; S=1; }
printf '%s\n' "$CAST_LSH" | grep -q 'object Object' \
  && { fail "cast layers shape" "the value was coerced into a layer name: $CAST_LSH"; S=1; }
printf '%s\n' "$CAST_LSH" | grep -q '^layers ' \
  && { fail "cast layers shape" "the run carried on and reported layers: $CAST_LSH"; S=1; }
cp "$CASTFIX/layers.bak" "$CAST_LAYERS"; rm -f "$CASTFIX/layers.bak"
# the layer names the fixture does write are still read
CAST_LOK="$(cd "$CASTFIX" && "$CAST_BIN" report 2>&1)"; RC=$?
[ "$RC" = 0 ] \
  || { fail "cast layers shape" "a layers.json of names exited $RC, not 0: $CAST_LOK"; S=1; }
[ "$S" = 0 ] && ok "cast layers shape"

# AC2 a module no glob claims is counted and named, never silently dropped
S=0
# break: skipping the unmatched modules instead of filing them as unassigned
printf '%s\n' "$CAST_REPORT" | grep -q '^unassigned 2$' \
  || { fail "cast unassigned" "cast report did not count the unassigned modules: $CAST_REPORT"; S=1; }
# break: reporting a count without the names, which says nothing to go and place
for m in pkg/one.toy pkg/two.toy; do
  printf '%s\n' "$CAST_REPORT" | grep -q "^  $m\$" \
    || { fail "cast unassigned" "cast report did not name the unassigned module $m: $CAST_REPORT"; S=1; }
done
# an unassigned module is not also counted inside a layer
# break: defaulting an unmatched module into the first declared layer
printf '%s\n' "$CAST_REPORT" | grep -q '^  ui 1$' \
  || { fail "cast unassigned" "an unassigned module was swept into a layer: $CAST_REPORT"; S=1; }
[ "$S" = 0 ] && ok "cast unassigned"

# AC3 cast edges --from --to lists the module edges behind one layer edge
S=0
CAST_EDGES="$(cd "$CASTFIX" && "$CAST_BIN" edges --from ui --to logic 2>&1)" \
  || { fail "cast edges" "cast edges did not run: $CAST_EDGES"; S=1; }
# every module edge behind the layer edge, each with its file and its line
# break: dropping the file or the line from the line, or listing only the first edge
for e in 'src/a.ts:1 -> src/b.ts' 'src/a.ts:2 -> src/t.ts' 'src/a.ts:6 -> src/c.ts'; do
  printf '%s\n' "$CAST_EDGES" | grep -q "^  $e " \
    || { fail "cast edges" "cast edges did not list $e: $CAST_EDGES"; S=1; }
done
printf '%s\n' "$CAST_EDGES" | grep -q '^module edges ui -> logic 3$' \
  || { fail "cast edges" "cast edges did not count the module edges: $CAST_EDGES"; S=1; }
# the direction is the layer edge asked for, not every edge that touches it
# break: ignoring --from and --to and listing the whole graph
CAST_BACK="$(cd "$CASTFIX" && "$CAST_BIN" edges --from logic --to ui 2>&1)"
printf '%s\n' "$CAST_BACK" | grep -q '^  src/c.ts:1 -> src/a.ts ' \
  || { fail "cast edges" "the reverse layer edge was not listed: $CAST_BACK"; S=1; }
printf '%s\n' "$CAST_BACK" | grep -q 'src/b.ts' \
  && { fail "cast edges" "an edge outside the layer edge was listed: $CAST_BACK"; S=1; }
[ "$S" = 0 ] && ok "cast edges"

# AC4 cast render --mermaid opens at layer altitude: one node per layer, no module
S=0
CAST_MMD="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid 2>&1)" \
  || { fail "cast altitude" "cast render --mermaid did not run: $CAST_MMD"; S=1; }
# break: emitting one node per module, the view every project is unreadable at
printf '%s\n' "$CAST_MMD" | grep -q 'src/' \
  && { fail "cast altitude" "a module node was emitted without --expand: $CAST_MMD"; S=1; }
# one node per layer, the unassigned modules included - a layer left out is a
# part of the project the picture denies
# break: rendering only the layers that carry an edge, or dropping unassigned
for l in 'ui (1)' 'logic (5)' 'unassigned (2)'; do
  printf '%s\n' "$CAST_MMD" | grep -q "\"$l\"" \
    || { fail "cast altitude" "no node for the layer $l: $CAST_MMD"; S=1; }
done
printf '%s\n' "$CAST_MMD" | grep -q '^graph ' \
  || { fail "cast altitude" "the output is not a mermaid graph: $CAST_MMD"; S=1; }
[ "$S" = 0 ] && ok "cast altitude"

# AC5 a layer edge carries the number of module edges behind it
S=0
# break: drawing the arrow without its label, or labelling it 1 per layer pair
# instead of counting the module edges layerEdges lists
printf '%s\n' "$CAST_MMD" | grep -q '^  L_ui -->|3| L_logic$' \
  || { fail "cast edge weight" "the ui -> logic edge is not weighted 3: $CAST_MMD"; S=1; }
printf '%s\n' "$CAST_MMD" | grep -q '^  L_logic -->|1| L_ui$' \
  || { fail "cast edge weight" "the logic -> ui edge is not weighted 1: $CAST_MMD"; S=1; }
# an edge inside one collapsed layer is not an arrow at this altitude
# break: emitting a self loop for the module edges within a layer
printf '%s\n' "$CAST_MMD" | grep -qE '^  (L_[A-Za-z_]+) -->\|[0-9]+\| \1$' \
  && { fail "cast edge weight" "a layer was given a self edge: $CAST_MMD"; S=1; }
[ "$S" = 0 ] && ok "cast edge weight"

# AC6 --expand resolves one layer to its modules and leaves the others alone
S=0
CAST_EXP="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid --expand logic 2>&1)" \
  || { fail "cast expand" "cast render --expand did not run: $CAST_EXP"; S=1; }
# break: ignoring --expand, which leaves the layer a single node
printf '%s\n' "$CAST_EXP" | grep -q '^  subgraph L_logic\["logic"\]$' \
  || { fail "cast expand" "the expanded layer is not a subgraph: $CAST_EXP"; S=1; }
for m in src/b.ts src/c.ts src/t.ts src/rel.ts src/multi.ts; do
  printf '%s\n' "$CAST_EXP" | grep -q "^    M_[A-Za-z0-9_]*\[\"$m\"\]" \
    || { fail "cast expand" "the module $m is not inside the expanded layer: $CAST_EXP"; S=1; }
done
# every other layer stays one node
# break: expanding the whole graph instead of the named layer
printf '%s\n' "$CAST_EXP" | grep -q '"ui (1)"' \
  || { fail "cast expand" "the ui layer did not stay a single node: $CAST_EXP"; S=1; }
printf '%s\n' "$CAST_EXP" | grep -q '"src/a.ts"' \
  && { fail "cast expand" "a module of an unexpanded layer became a node: $CAST_EXP"; S=1; }
# the edge into the expanded layer lands on the module, not the layer node
# break: keeping the layer endpoint after expanding, which hides what is imported
printf '%s\n' "$CAST_EXP" | grep -q '^  L_ui -->|1| M_src_2f_b_2e_ts$' \
  || { fail "cast expand" "an edge into the expanded layer did not reach a module: $CAST_EXP"; S=1; }
[ "$S" = 0 ] && ok "cast expand"

# two modules whose ids differ only in punctuation are two nodes, never one
S=0
# a fixture of its own: the ids have to collide under a lossy sanitiser, and the
# layer sizes the suites above assert must not move
mkdir -p "$CASTIDS/src"
printf 'export const a = 1\n' > "$CASTIDS/src/x-y.ts"
printf 'export const b = 2\n' > "$CASTIDS/src/x_y.ts"
(cd "$CASTIDS" && "$CAST_BIN" scan >/dev/null 2>&1) \
  || { fail "cast node ids" "cast scan did not run on the collision fixture"; S=1; }
CAST_IDS="$(cd "$CASTIDS" && "$CAST_BIN" render --mermaid --expand src 2>&1)"
node_of() { printf '%s\n' "$CAST_IDS" | sed -n "s/^ *\(M_[A-Za-z0-9_]*\)\[\"$1\"\]\$/\1/p"; }
ID_A="$(node_of 'src\/x-y\.ts')"
ID_B="$(node_of 'src\/x_y\.ts')"
# break: mapping every character mermaid rejects to a bare `_`, which gives both
# modules the id M_src_x_y_ts - one node drawn for two modules, and an edge of
# one of them silently attributed to the other
[ -n "$ID_A" ] && [ -n "$ID_B" ] \
  || { fail "cast node ids" "a module was not drawn as its own node: $CAST_IDS"; S=1; }
[ "$ID_A" != "$ID_B" ] \
  || { fail "cast node ids" "two modules share the node id $ID_A: $CAST_IDS"; S=1; }
[ "$S" = 0 ] && ok "cast node ids"

# AC7 cast render --html writes one self-contained page carrying the layer names
S=0
CAST_HTML_OUT="$(cd "$CASTFIX" && "$CAST_BIN" render --html view.html 2>&1)" \
  || { fail "cast html" "cast render --html did not run: $CAST_HTML_OUT"; S=1; }
# break: rendering to stdout and writing no file
[ -f "$CASTFIX/view.html" ] \
  || { fail "cast html" "cast render --html wrote no page: $CAST_HTML_OUT"; S=1; }
CAST_HTML="$(cat "$CASTFIX/view.html" 2>/dev/null)"
# break: writing the mermaid source under an .html name, with no page around it
printf '%s\n' "$CAST_HTML" | grep -qi '<html' \
  || { fail "cast html" "the page is not html: $CAST_HTML"; S=1; }
# the layer names are the whole claim
# break: emitting the graph without ever naming a layer
for l in ui logic unassigned; do
  printf '%s\n' "$CAST_HTML" | grep -q "$l" \
    || { fail "cast html" "the page does not carry the layer $l: $CAST_HTML"; S=1; }
done
# self-contained: it fetches nothing
# break: pulling mermaid off a cdn, which makes the page useless offline
printf '%s\n' "$CAST_HTML" | grep -qE 'src="https?:|href="https?:' \
  && { fail "cast html" "the page loads an external asset: $CAST_HTML"; S=1; }
# AC9 (of #47) the legend says how to ask for a number, and neither it nor the
# README still claims an arrow carries its count on the page
# break: taking the counts off the drawing and leaving the prose describing them
printf '%s\n' "$CAST_HTML" | grep -qF 'press and hold it on a touch screen' \
  || { fail "cast html" "the legend never says how to ask a node for its numbers"; S=1; }
printf '%s\n' "$CAST_HTML" | grep -qF 'says under its count' \
  && { fail "cast html" "the legend still says an arrow carries its count"; S=1; }
grep -qF 'pressing and holding it on a touch screen' plugins/cast/README.md \
  || { fail "cast html" "README.md never says how to ask a node for its numbers"; S=1; }
grep -qF 'The label sits beside the lane the curve' plugins/cast/README.md \
  && { fail "cast html" "README.md still places a count beside the lane"; S=1; }
grep -qF 'is labelled with the number of' plugins/cast/README.md \
  && { fail "cast html" "README.md still says an arrow on the page is labelled with its count"; S=1; }
[ "$S" = 0 ] && ok "cast html"

# #56 the page can be published as an artifact: a fragment with no document of
# its own, painted from theme tokens, with a mermaid block a host can draw
S=0
CAST_FRAG_OUT="$(cd "$CASTFIX" && "$CAST_BIN" render --html frag.html --fragment 2>&1)" \
  || { fail "cast artifact page" "cast render --html --fragment did not run: $CAST_FRAG_OUT"; S=1; }
[ -f "$CASTFIX/frag.html" ] \
  || { fail "cast artifact page" "--fragment wrote no page: $CAST_FRAG_OUT"; S=1; }
CAST_FRAG="$(cat "$CASTFIX/frag.html" 2>/dev/null)"
# AC1 the host supplies the skeleton and rejects a second one
# break: writing the document around the content in fragment mode too
for t in '<!doctype' '<html' '<head>' '<head ' '<body>' '<body '; do
  printf '%s\n' "$CAST_FRAG" | grep -qiF "$t" \
    && { fail "cast artifact page" "the fragment carries its own $t"; S=1; }
done
# AC1 the title is what names the page, and only the head of the file is read
# break: dropping the title with the head that used to carry it
# break: naming every page `cast`, which tells no two of them apart in a list
CAST_FRAG_TITLE="$(printf '%s' "$CAST_FRAG" | head -c 8192 | sed -n 's|.*<title>\(.*\)</title>.*|\1|p' | head -1)"
case "$CAST_FRAG_TITLE" in
  *' module graph') : ;;
  *) fail "cast artifact page" "the fragment names itself '$CAST_FRAG_TITLE' in its first 8 KB"; S=1 ;;
esac
# the project the page read is the half of that name that tells it apart
CAST_FIX_NAME="$(basename "$CASTFIX")"
case "$CAST_FRAG_TITLE" in
  "$CAST_FIX_NAME"*) : ;;
  *) fail "cast artifact page" "the title '$CAST_FRAG_TITLE' does not name the project $CAST_FIX_NAME"; S=1 ;;
esac
# AC2 the standalone page is unchanged
# break: making the fragment the only shape the renderer knows
for t in '<!doctype html>' '<head' '<body' 'width=device-width'; do
  printf '%s\n' "$CAST_HTML" | grep -qiF "$t" \
    || { fail "cast artifact page" "the standalone page lost $t"; S=1; }
done
# AC6 a fragment fetches nothing either
# break: reaching for a mermaid library once a host is drawing the block
printf '%s\n' "$CAST_FRAG" | grep -qE 'src="https?:|href="https?:' \
  && { fail "cast artifact page" "the fragment loads an external asset"; S=1; }
# the page draws the graph once: the mermaid source is `render --mermaid`, and a
# copy of it below a drawing that opens every node said less than the drawing did
# break: putting the block back, marked or bare
for f in "$CASTFIX/frag.html" "$CASTFIX/view.html"; do
  for t in '<h2>mermaid</h2>' '<pre id="mermaid"' 'class="mermaid"' 'graph LR'; do
    grep -qF "$t" "$f" \
      && { fail "cast artifact page" "$f still carries the mermaid block: $t"; S=1; }
  done
done
# the source itself is unchanged where it is asked for
# break: taking the block off the page by taking the render with it
CAST_MM_STILL="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid 2>&1)"
printf '%s\n' "$CAST_MM_STILL" | grep -q '^graph LR$' \
  || { fail "cast artifact page" "cast render --mermaid no longer draws: $CAST_MM_STILL"; S=1; }
# AC3, AC4 every colour is a token on bare `:root`, redefined both ways a theme
# is asked for, and the ground is painted rather than inherited
# break: putting `.node rect{fill:#eef3fb}` back as a literal, or defining a
# colour only inside the dark block, which leaves it undefined in the light one
CAST_THEME="$(node -e '
const fs=require("fs");
for (const f of process.argv.slice(1)) {
  const p=fs.readFileSync(f,"utf8");
  const m=p.match(/<style>([\s\S]*?)<\/style>/);
  if(!m){ console.log(f+": no stylesheet"); continue }
  const css=m[1];
  if(!/:root\{[^}]*--/.test(css)) console.log(f+": no tokens on bare :root");
  if(!/@media \(prefers-color-scheme:dark\)\{:root:not\(\[data-theme="light"\]\)\{/.test(css))
    console.log(f+": no guarded prefers-color-scheme block");
  if(!/:root\[data-theme="dark"\]\{/.test(css)) console.log(f+": no data-theme block");
  if(!/body\{[^}]*background:var\(--/.test(css)) console.log(f+": body paints no background of its own");
  const rest=css.replace(/:root[^{]*\{[^}]*\}/g,"").replace(/@media[^{]*\{[^{]*\{[^}]*\}\}/g,"");
  const hex=rest.match(/#[0-9a-fA-F]{3,8}/g);
  if(hex) console.log(f+": a colour outside the tokens: "+hex.join(" "));
}' "$CASTFIX/frag.html" "$CASTFIX/view.html" 2>&1)"
[ -z "$CAST_THEME" ] \
  || { fail "cast artifact page" "the page does not paint from theme tokens: $CAST_THEME"; S=1; }
# the drawing takes the arrow colour from the same sheet
# break: `stroke: e.color`, which paints a light theme's red on a dark ground
grep -qF "'var(--edge-' + e.tone + ')'" plugins/cast/scripts/cast.js \
  || { fail "cast artifact page" "the drawn arrow no longer takes its colour from the sheet"; S=1; }
# AC1 the flag answers a question only --html asks
# break: accepting --fragment beside --mermaid and silently ignoring it
CAST_FRAG_BAD="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid --fragment 2>&1)"; RC=$?
[ "$RC" = 2 ] \
  || { fail "cast artifact page" "--fragment without --html exited $RC: $CAST_FRAG_BAD"; S=1; }
# AC7, AC8 the rule, the skills and the README name the way the page is delivered
# break: shipping the flag and leaving every caller sending the standalone file
grep -qF -- '--fragment' plugins/cast/README.md \
  || { fail "cast artifact page" "README.md does not document --fragment"; S=1; }
grep -qF 'Artifact' plugins/cast/rules/cast.md \
  || { fail "cast artifact page" "the rule does not name publishing the page as an Artifact"; S=1; }
grep -qF -- '--fragment' plugins/cast/rules/cast.md \
  || { fail "cast artifact page" "the rule does not render the page as a fragment"; S=1; }
for f in plugins/cast/skills/map/SKILL.md plugins/cast/skills/plan/SKILL.md; do
  grep -qF -- '--fragment' "$f" \
    || { fail "cast artifact page" "$f does not render the page as a fragment"; S=1; }
  grep -qF 'Artifact' "$f" \
    || { fail "cast artifact page" "$f does not publish the page"; S=1; }
done
# the document opens on the graph and its counts: what a press does is at the
# foot, shut, and nothing before the drawing is prose
# break: putting the reading guide back at the top, where it introduces a page
# whose first screen is the answer
CAST_LEGEND="$(sed -n '/<details class="legend">/,/<\/details>/p' "$CASTFIX/frag.html")"
printf '%s\n' "$CAST_LEGEND" | grep -qF 'press and hold it on a touch screen' \
  || { fail "cast artifact page" "the reading guide is not shut at the foot of the page"; S=1; }
CAST_BEFORE="$(sed -n '1,/<div id="graph-scroll">/p' "$CASTFIX/frag.html")"
printf '%s\n' "$CAST_BEFORE" | grep -qE '^<p>' \
  && { fail "cast artifact page" "the page introduces itself before it draws anything"; S=1; }
# the two faces: a sans for the chrome, a mono wherever the page shows something
# the project itself named - the project, a file, a count
# break: one face for everything, which sets a path in the type of a sentence
for r in 'h1{margin:0;font:600 clamp(26px,4vw,38px)/1.15 ui-monospace' \
         '.node text{font:14px ui-monospace' \
         'font-variant-numeric:tabular-nums'; do
  grep -qF "$r" "$CASTFIX/frag.html" \
    || { fail "cast artifact page" "the page does not set $r"; S=1; }
done
rm -f "$CASTFIX/frag.html"
[ "$S" = 0 ] && ok "cast artifact page"


# --- cast: the rules ---------------------------------------------------------
# The same scanned fixture, read through .cast/rules.json. Rules are read at
# check time, so every case here rewrites the file and rescans nothing.
CAST_RULES="$CASTFIX/.cast/rules.json"

# AC1 rules.json holds forbidden and allowed rules, each with name, severity,
# from, to and kinds, and a side is a layer or a path
S=0
cat > "$CAST_RULES" <<'JSON'
{
  "forbidden": [
    { "name": "ui-owns-nothing", "severity": "error", "from": "ui", "to": "logic",
      "kinds": ["value", "type", "dynamic"] }
  ],
  "allowed": [
    { "name": "a-may-type-t", "severity": "error", "from": "src/a.ts", "to": "src/t.ts",
      "kinds": ["type"] }
  ]
}
JSON
CAST_CHECK="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"
# a forbidden rule written between two layers catches the edges behind them
# break: reading `from`/`to` as a path only, which leaves a layer rule matching nothing
for v in 'src/a.ts:1 -> src/b.ts' 'src/a.ts:6 -> src/c.ts'; do
  printf '%s\n' "$CAST_CHECK" | grep -q "$v" \
    || { fail "cast rules" "the forbidden layer rule did not catch $v: $CAST_CHECK"; S=1; }
done
# an allowed rule, written between two paths, is the exception to it
# break: ignoring the allowed list, which makes every exception unwritable
printf '%s\n' "$CAST_CHECK" | grep -q 'src/a.ts:2' \
  && { fail "cast rules" "an edge an allowed rule claims was still a violation: $CAST_CHECK"; S=1; }
printf '%s\n' "$CAST_CHECK" | grep -q '^2 violations' \
  || { fail "cast rules" "the violations were not counted: $CAST_CHECK"; S=1; }
# a rule attribute the evaluator cannot decide is named, never quietly passed
# break: dropping the unknown-key report, which reads as a rule that held
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "guess", "severity": "warn", "from": "ui", "to": "unassigned",
                   "kinds": ["value"], "unless": "friday" } ] }
JSON
CAST_UNK="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"
printf '%s\n' "$CAST_UNK" | grep -q 'not evaluated: guess: unless' \
  || { fail "cast rules" "an attribute the evaluator cannot decide was passed silently: $CAST_UNK"; S=1; }
[ "$S" = 0 ] && ok "cast rules"

# AC2 a project that breaks no rule exits 0 with a single line
S=0
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "ui-off-pkg", "severity": "error", "from": "ui", "to": "unassigned",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
CAST_CLEAN="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"; RC=$?
# break: exiting non-zero on a graph that breaks nothing
[ "$RC" = 0 ] || { fail "cast check clean" "a clean project did not exit 0: $CAST_CLEAN"; S=1; }
# break: printing a header, or a line per rule, above the answer
[ "$(printf '%s\n' "$CAST_CLEAN" | wc -l)" = 1 ] \
  || { fail "cast check clean" "a clean check answered in more than one line: $CAST_CLEAN"; S=1; }
printf '%s\n' "$CAST_CLEAN" | grep -q '^0 violations' \
  || { fail "cast check clean" "the one line does not say the project is clean: $CAST_CLEAN"; S=1; }
[ "$S" = 0 ] && ok "cast check clean"

# AC3 a violated error rule exits 1 and names every violation, grouped by rule
# and layer edge
S=0
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "no-back-edge", "severity": "error", "from": "logic", "to": "ui",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
CAST_BAD="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"; RC=$?
# break: reporting the violation and still exiting 0, which lets the build pass
[ "$RC" = 1 ] || { fail "cast check violation" "a violated error rule exited $RC, not 1: $CAST_BAD"; S=1; }
# the rule, the file and the line: a violation without its site is unopenable
# break: dropping the site from the line, or naming the count only
printf '%s\n' "$CAST_BAD" | grep -q '^no-back-edge (error) logic -> ui 1$' \
  || { fail "cast check violation" "the violations are not grouped under their rule: $CAST_BAD"; S=1; }
printf '%s\n' "$CAST_BAD" | grep -q '^  logic -> ui 1$' \
  || { fail "cast check violation" "the violations are not grouped by layer edge: $CAST_BAD"; S=1; }
printf '%s\n' "$CAST_BAD" | grep -q '^    src/c.ts:1 -> src/a.ts (value)$' \
  || { fail "cast check violation" "the violation does not carry its file and line: $CAST_BAD"; S=1; }
[ "$S" = 0 ] && ok "cast check violation"

# AC4 the same rule at severity warn is listed and leaves the exit code 0
S=0
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "no-back-edge", "severity": "warn", "from": "logic", "to": "ui",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
CAST_WARN="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"; RC=$?
# break: reading severity as decoration, which fails the build on a warning
[ "$RC" = 0 ] || { fail "cast severity" "a warn rule exited $RC, not 0: $CAST_WARN"; S=1; }
# break: silencing what does not fail, which makes a warning unfindable
printf '%s\n' "$CAST_WARN" | grep -q '^no-back-edge (warn) logic -> ui 1$' \
  || { fail "cast severity" "a warn violation was not listed: $CAST_WARN"; S=1; }
printf '%s\n' "$CAST_WARN" | grep -q '^    src/c.ts:1 -> src/a.ts (value)$' \
  || { fail "cast severity" "a warn violation was listed without its site: $CAST_WARN"; S=1; }
printf '%s\n' "$CAST_WARN" | grep -q '(0 errors)' \
  || { fail "cast severity" "a warn violation was counted as an error: $CAST_WARN"; S=1; }
[ "$S" = 0 ] && ok "cast severity"

# AC5 a rule carrying kinds: ["value"] is not violated by an import type edge
S=0
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "rel-off-t", "severity": "error", "from": "src/rel.ts", "to": "src/t.ts",
                   "kinds": ["value"] } ] }
JSON
CAST_KIND="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"; RC=$?
# src/rel.ts imports src/t.ts with `import type` and nothing else
# break: evaluating a rule over every edge whatever its kind
[ "$RC" = 0 ] || { fail "cast kinds" "a value rule was violated by a type edge: $CAST_KIND"; S=1; }
printf '%s\n' "$CAST_KIND" | grep -q '^0 violations' \
  || { fail "cast kinds" "a value rule caught a type edge: $CAST_KIND"; S=1; }
# and the same rule over the kind that is there does catch it
# break: dropping every edge whose kind is not value, which would pass either way
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "rel-off-t", "severity": "error", "from": "src/rel.ts", "to": "src/t.ts",
                   "kinds": ["type"] } ] }
JSON
CAST_KIND2="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"; RC=$?
[ "$RC" = 1 ] || { fail "cast kinds" "the type edge was not caught by a type rule: $CAST_KIND2"; S=1; }
printf '%s\n' "$CAST_KIND2" | grep -q '^    src/rel.ts:1 -> src/t.ts (type)$' \
  || { fail "cast kinds" "the type edge was not named: $CAST_KIND2"; S=1; }
[ "$S" = 0 ] && ok "cast kinds"

# AC6 a violation inside one layer is still found: the check reads the module
# graph, never the aggregate the render draws
S=0
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "b-off-c", "severity": "error", "from": "src/b.ts", "to": "src/c.ts",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
CAST_IN="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"; RC=$?
# src/b.ts and src/c.ts are both in `logic`, so this edge has no arrow at layer
# altitude at all - the render drops it as a self edge
# break: evaluating the rules over the layer edges the render aggregates, which
# never carries an edge whose endpoints collapse to one node
[ "$RC" = 1 ] || { fail "cast check altitude" "an edge inside one layer was not checked: $CAST_IN"; S=1; }
printf '%s\n' "$CAST_IN" | grep -q '^    src/b.ts:1 -> src/c.ts (value)$' \
  || { fail "cast check altitude" "the intra-layer violation was not named with its site: $CAST_IN"; S=1; }
printf '%s\n' "$CAST_IN" | grep -q '^  logic -> logic 1$' \
  || { fail "cast check altitude" "the intra-layer violation lost its layer edge: $CAST_IN"; S=1; }
[ "$S" = 0 ] && ok "cast check altitude"

# AC7 bin/cast-check runs the check without arguments, on the wrapper contract
S=0
CAST_CHECK_BIN="$PWD/plugins/cast/bin/cast-check"
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "ui-off-pkg", "severity": "error", "from": "ui", "to": "unassigned",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
CAST_W="$(cd "$CASTFIX" && "$CAST_CHECK_BIN" 2>&1)"; RC=$?
# break: requiring a subcommand or a --root, which no check command passes
[ "$RC" = 0 ] || { fail "cast check wrapper" "the wrapper exited $RC on a clean project: $CAST_W"; S=1; }
[ "$(printf '%s\n' "$CAST_W" | wc -l)" = 1 ] \
  || { fail "cast check wrapper" "a green wrapper run answered in more than one line: $CAST_W"; S=1; }
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "no-back-edge", "severity": "error", "from": "logic", "to": "ui",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
CAST_W1="$(cd "$CASTFIX" && "$CAST_CHECK_BIN" 2>&1)"; RC=$?
# break: swallowing the check's exit code, which reports every red run as green
[ "$RC" = 1 ] || { fail "cast check wrapper" "the wrapper exited $RC on a violation: $CAST_W1"; S=1; }
printf '%s\n' "$CAST_W1" | grep -q '^    src/c.ts:1 -> src/a.ts (value)$' \
  || { fail "cast check wrapper" "the wrapper dropped the detail of the failure: $CAST_W1"; S=1; }
# exit 2 is the third answer: the check could not run
# break: reporting a broken rules file as a violation, or as a pass
printf 'not json\n' > "$CAST_RULES"
CAST_W2="$(cd "$CASTFIX" && "$CAST_CHECK_BIN" 2>&1)"; RC=$?
[ "$RC" = 2 ] || { fail "cast check wrapper" "an unreadable rules file exited $RC, not 2: $CAST_W2"; S=1; }
[ "$S" = 0 ] && ok "cast check wrapper"


# AC3 a rule side that is present but is not a string is rejected for its shape,
# never as a side that is absent
S=0
# the rule reaches readRule through rules.json - the one path there is since
# `cast rules preview` was dropped for `severity: "warn"`
try_rule() { printf '{ "forbidden": [ %s ] }\n' "$1" > "$CAST_RULES"; (cd "$CASTFIX" && "$CAST_BIN" check 2>&1); }
CAST_RSH="$(try_rule '{"name":"r","from":3,"to":"logic"}')"; RC=$?
[ "$RC" = 2 ] \
  || { fail "cast rule shape" "a rule with a non-string from exited $RC, not 2: $CAST_RSH"; S=1; }
# break: letting side() answer null for a wrong shape and a missing key alike,
# which sends the author looking for a key that is in the file
printf '%s\n' "$CAST_RSH" | grep -qF 'has from 3, not a layer name or a path glob' \
  || { fail "cast rule shape" "the shape that was expected was not named: $CAST_RSH"; S=1; }
printf '%s\n' "$CAST_RSH" | grep -q 'carries no from' \
  && { fail "cast rule shape" "a present from was reported as absent: $CAST_RSH"; S=1; }
CAST_RSH2="$(try_rule '{"name":"r","from":"ui","to":["logic"]}')"; RC=$?
[ "$RC" = 2 ] \
  || { fail "cast rule shape" "a rule with a non-string to exited $RC, not 2: $CAST_RSH2"; S=1; }
printf '%s\n' "$CAST_RSH2" | grep -qF 'has to ["logic"], not a layer name or a path glob' \
  || { fail "cast rule shape" "the shape expected of to was not named: $CAST_RSH2"; S=1; }
# a side that really is absent still says so - break: reporting every side by its
# shape, which leaves a forgotten key describing itself as undefined
CAST_RSH3="$(try_rule '{"name":"r","to":"logic"}')"; RC=$?
[ "$RC" = 2 ] \
  || { fail "cast rule shape" "a rule with no from exited $RC, not 2: $CAST_RSH3"; S=1; }
printf '%s\n' "$CAST_RSH3" | grep -q 'carries no from' \
  || { fail "cast rule shape" "an absent from was not reported as absent: $CAST_RSH3"; S=1; }
[ "$S" = 0 ] && ok "cast rule shape"

# AC8 a violation listed in .cast/baseline.json leaves the check green; one that
# is not listed turns it red
S=0
CAST_BASE="$CASTFIX/.cast/baseline.json"
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "no-back-edge", "severity": "error", "from": "logic", "to": "ui",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
cat > "$CAST_BASE" <<'JSON'
{ "violations": [ { "rule": "no-back-edge", "file": "src/c.ts", "to": "src/a.ts", "kind": "value" } ] }
JSON
CAST_B="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"; RC=$?
# break: checking without reading the baseline, which fails a build on inherited debt
[ "$RC" = 0 ] || { fail "cast baseline" "a baselined violation exited $RC, not 0: $CAST_B"; S=1; }
# break: holding a violation silently, which hides the size of the debt
printf '%s\n' "$CAST_B" | grep -q '1 baselined' \
  || { fail "cast baseline" "the held violation was not counted in the summary: $CAST_B"; S=1; }
printf '%s\n' "$CAST_B" | grep -q '^0 violations (0 errors)' \
  || { fail "cast baseline" "a baselined violation was still counted as live: $CAST_B"; S=1; }
# two violations, one of them listed: the unlisted one is still red and still named
# break: reading the baseline as a switch per rule, or as "any entry means green"
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "ui-off-logic", "severity": "error", "from": "ui", "to": "logic",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
cat > "$CAST_BASE" <<'JSON'
{ "violations": [ { "rule": "ui-off-logic", "file": "src/a.ts", "to": "src/b.ts", "kind": "value" } ] }
JSON
CAST_B2="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"; RC=$?
[ "$RC" = 1 ] || { fail "cast baseline" "an unlisted violation exited $RC, not 1: $CAST_B2"; S=1; }
printf '%s\n' "$CAST_B2" | grep -q '^    src/a.ts:6 -> src/c.ts (dynamic)$' \
  || { fail "cast baseline" "the unlisted violation was not named: $CAST_B2"; S=1; }
printf '%s\n' "$CAST_B2" | grep -q 'src/a.ts:1 -> src/b.ts' \
  && { fail "cast baseline" "the baselined violation was listed as live: $CAST_B2"; S=1; }
[ "$S" = 0 ] && ok "cast baseline"

# AC9 cast baseline --update refuses a baseline holding more violations than the
# one it replaces
S=0
# the rules above are violated twice, the baseline on disk holds one
CAST_R1="$(cd "$CASTFIX" && "$CAST_BIN" baseline --update 2>&1)"; RC=$?
# break: writing the current violations unconditionally, which lets debt grow
[ "$RC" = 1 ] || { fail "cast ratchet" "growing the baseline exited $RC, not 1: $CAST_R1"; S=1; }
printf '%s\n' "$CAST_R1" | grep -q 'refused' \
  || { fail "cast ratchet" "the refusal did not say it refused: $CAST_R1"; S=1; }
# break: refusing but writing anyway, which is the same growth one run later
grep -q 'src/c.ts' "$CAST_BASE" \
  && { fail "cast ratchet" "the refused baseline was written to disk: $(cat "$CAST_BASE")"; S=1; }
# a baseline that shrinks is written, and the check is green on it
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "no-back-edge", "severity": "error", "from": "logic", "to": "ui",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
CAST_R2="$(cd "$CASTFIX" && "$CAST_BIN" baseline --update 2>&1)"; RC=$?
# break: refusing every update, which makes the baseline unwritable
[ "$RC" = 0 ] || { fail "cast ratchet" "an equal-sized baseline exited $RC, not 0: $CAST_R2"; S=1; }
grep -q 'src/c.ts' "$CAST_BASE" \
  || { fail "cast ratchet" "the accepted baseline was not written: $(cat "$CAST_BASE")"; S=1; }
CAST_R3="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)"; RC=$?
[ "$RC" = 0 ] || { fail "cast ratchet" "the written baseline did not hold its violation: $CAST_R3"; S=1; }
rm -f "$CAST_BASE"
[ "$S" = 0 ] && ok "cast ratchet"


# --- cast: a plan, simulated -------------------------------------------------
# The same scanned fixture, read through .cast/plans/<name>.json. A plan is
# applied to a copy of the graph, so every case here rescans nothing and every
# case leaves the fixture exactly as it found it.
mkdir -p "$CASTFIX/.cast/plans"
cat > "$CASTFIX/.cast/plans/cut.json" <<'JSON'
{ "operations": [
  { "op": "move", "module": "src/rel.ts", "to": "pkg/rel.ts" },
  { "op": "merge", "modules": ["src/b.ts", "src/c.ts"], "into": "src/bc.ts" },
  { "op": "invert", "from": "src/a.ts", "to": "src/bc.ts" },
  { "op": "invert", "from": "src/a.ts", "to": "src/t.ts" },
  { "op": "split", "module": "src/multi.ts",
    "into": [ { "id": "src/multi-core.ts", "imports": ["src/t.ts"] },
              { "id": "src/multi-shell.ts" } ] }
] }
JSON

# AC1 the plan file holds an ordered list of move, split, merge and invert, and
# the simulation applies them to a copy of the graph
S=0
CAST_PLAN="$(cd "$CASTFIX" && "$CAST_BIN" plan simulate cut 2>&1)"; RC=$?
# break: dying on an operation kind the plan may hold, or on the plan file itself
[ "$RC" = 0 ] || { fail "cast plan" "simulating the plan exited $RC: $CAST_PLAN"; S=1; }
# every operation is named, in the order the file writes them
# break: applying the operations but never saying which ones were applied
for o in 'move src/rel.ts -> pkg/rel.ts' \
         'merge src/b.ts, src/c.ts -> src/bc.ts' \
         'invert src/a.ts -> src/bc.ts' \
         'invert src/a.ts -> src/t.ts' \
         'split src/multi.ts -> src/multi-core.ts, src/multi-shell.ts'; do
  printf '%s\n' "$CAST_PLAN" | grep -qF "$o" \
    || { fail "cast plan" "the plan did not report the operation $o: $CAST_PLAN"; S=1; }
done
# the operations are ordered: the invert names a module only the merge before it
# creates, so an unordered or independently applied plan cannot resolve it
# break: applying each operation to the graph as scanned instead of to the graph
# the operation before it left behind, which makes src/bc.ts an unknown module
printf '%s\n' "$CAST_PLAN" | grep -q 'no module src/bc.ts' \
  && { fail "cast plan" "the operations were not applied in order: $CAST_PLAN"; S=1; }
# the graph really changed: the merge dropped the edge between the merged pair
# and the invert turned two edges around
# break: reporting the plan and comparing the graph with itself
printf '%s\n' "$CAST_PLAN" | grep -q '^module edges 8 -> 7' \
  || { fail "cast plan" "the operations did not reach the copied graph: $CAST_PLAN"; S=1; }
[ "$S" = 0 ] && ok "cast plan"

# a plan is a name or a path, so a draft never has to be written into the
# checkout to be simulated - the agents keep theirs in a scratch directory
S=0
PLANDIR="$(mktemp -d)"
cp "$CASTFIX/.cast/plans/cut.json" "$PLANDIR/cut.json"
# break: resolving every argument under <root>/.cast/plans, which makes a plan
# outside the checkout unreadable and the scratch draft impossible
CAST_PP="$(cd "$CASTFIX" && "$CAST_BIN" plan simulate "$PLANDIR/cut.json" 2>&1)"; RC=$?
[ "$RC" = 0 ] || { fail "cast plan path" "a plan given by path exited $RC: $CAST_PP"; S=1; }
printf '%s\n' "$CAST_PP" | grep -q '^module edges 8 -> 7' \
  || { fail "cast plan path" "the plan at a path was not applied: $CAST_PP"; S=1; }
# break: naming the plan by its whole path, which puts a scratch directory in
# every line of the report
printf '%s\n' "$CAST_PP" | grep -q '^plan cut ' \
  || { fail "cast plan path" "the plan at a path is not named by its basename: $CAST_PP"; S=1; }
# --plan resolves the same way, or the page and the simulation disagree on what
# a plan argument means
# break: teaching only `plan simulate` about paths and leaving render behind
CAST_PR2="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid --plan "$PLANDIR/cut.json" 2>&1)"; RC=$?
[ "$RC" = 0 ] || { fail "cast plan path" "rendering a plan given by path exited $RC: $CAST_PR2"; S=1; }
printf '%s\n' "$CAST_PR2" | grep -q '^graph LR' \
  || { fail "cast plan path" "the plan at a path drew no graph: $CAST_PR2"; S=1; }
# a bare name still means the project's own plan
# break: reading every argument as a path, which breaks `plan simulate <name>`
CAST_PN="$(cd "$CASTFIX" && "$CAST_BIN" plan simulate cut 2>&1)"; RC=$?
[ "$RC" = 0 ] || { fail "cast plan path" "a plan given by name exited $RC: $CAST_PN"; S=1; }
# and a name that is nowhere says where it looked, relatively - break: printing
# the absolute path of a file inside the root, or `../..` for one outside it
CAST_PM="$(cd "$CASTFIX" && "$CAST_BIN" plan simulate nosuch 2>&1)"; RC=$?
[ "$RC" = 2 ] || { fail "cast plan path" "a missing plan exited $RC, not 2: $CAST_PM"; S=1; }
printf '%s\n' "$CAST_PM" | grep -qxF 'no plan at .cast/plans/nosuch.json' \
  || { fail "cast plan path" "a missing plan did not say where it looked: $CAST_PM"; S=1; }
CAST_PM2="$(cd "$CASTFIX" && "$CAST_BIN" plan simulate "$PLANDIR/nosuch.json" 2>&1)"; RC=$?
printf '%s\n' "$CAST_PM2" | grep -qxF "no plan at $PLANDIR/nosuch.json" \
  || { fail "cast plan path" "a missing plan outside the root was not named absolutely: $CAST_PM2"; S=1; }
rm -rf "$PLANDIR"
[ "$S" = 0 ] && ok "cast plan path"

# every edge the simulation produces names a site in the module that holds it
S=0
# a simulation writes nothing, so the after graph is read in process: stdout
# carries only the edges a rule flags, and this is about all of them
CAST_SITES="$(CASTFIX="$CASTFIX" CAST_GRAPH_FILE="$CAST_GRAPH_FILE" CAST_JS="$PWD/plugins/cast/scripts/cast.js" node -e '
  const cast = require(process.env.CAST_JS)
  const root = process.env.CASTFIX
  const graph = JSON.parse(require("fs").readFileSync(process.env.CAST_GRAPH_FILE, "utf8"))
  const after = cast.simulateGraph(graph, cast.readPlan(root, "cut"))
  const bad = []
  for (const m of after.modules)
    for (const e of m.edges)
      if (e.file !== m.id) bad.push(m.id + " holds an edge sited in " + e.file)
  const t = after.modules.find((x) => x.id === "src/t.ts")
  const inv = ((t || {}).edges || []).find((e) => e.to === "src/a.ts")
  if (!inv) bad.push("the inverted edge did not land on src/t.ts")
  else if (inv.line !== 0)
    bad.push("the inverted edge names line " + inv.line + ", a line of the file it came from")
  console.log(bad.join("; "))
' 2>&1)"
# break: renaming the module a move or a merge produces without retargeting the
# sites of its edges, which names a file the plan has just retired
[ -z "$CAST_SITES" ] || { fail "cast plan sites" "$CAST_SITES"; S=1; }
[ "$S" = 0 ] && ok "cast plan sites"

# AC2 every source file is byte-identical before and after the simulation
S=0
sums() { (cd "$CASTFIX" && find . -type f | sort | xargs cksum); }
CAST_BEFORE="$(sums)"
CAST_RO="$(cd "$CASTFIX" && "$CAST_BIN" plan simulate cut 2>&1)"; RC=$?
CAST_AFTER="$(sums)"
# a run that died changed nothing either, and would pass this suite for the wrong
# reason - the simulation has to have happened
[ "$RC" = 0 ] || { fail "cast plan readonly" "the simulation exited $RC: $CAST_RO"; S=1; }
# break: applying the operations to the loaded graph and writing it back, or
# executing the moves against the source tree - a simulation that costs a diff
[ "$CAST_BEFORE" = "$CAST_AFTER" ] \
  || { fail "cast plan readonly" "the simulation changed the project: $(diff <(printf '%s\n' "$CAST_BEFORE") <(printf '%s\n' "$CAST_AFTER"))"; S=1; }
[ "$S" = 0 ] && ok "cast plan readonly"

# AC3 cycles, fan-in, fan-out and instability, before and after
S=0
# the fixture's a -> b -> c -> a cycle survives the merge and is broken by the
# invert, and both sides of that are reported
# break: reporting the after only, which leaves the reader to remember today
printf '%s\n' "$CAST_PLAN" | grep -q '^cycles 1 -> 0' \
  || { fail "cast plan metrics" "the cycles were not counted before and after: $CAST_PLAN"; S=1; }
printf '%s\n' "$CAST_PLAN" | grep -q 'cycle: src/a.ts -> src/b.ts -> src/c.ts' \
  || { fail "cast plan metrics" "the cycle the plan breaks was not named: $CAST_PLAN"; S=1; }
# fan-in, fan-out and instability per layer, both sides. The invert moves ui from
# three outgoing edges to none, and the move puts a module in another layer.
# break: computing the metrics on the scanned graph for both columns
for m in 'ui fan-in 1 -> 4, fan-out 3 -> 0, instability 0.75 -> 0.00' \
         'logic fan-in 3 -> 1, fan-out 1 -> 4, instability 0.25 -> 0.80' \
         'unassigned fan-in 0 -> 0, fan-out 0 -> 1, instability 0.00 -> 1.00'; do
  printf '%s\n' "$CAST_PLAN" | grep -qF "$m" \
    || { fail "cast plan metrics" "the metrics line $m is not in the report: $CAST_PLAN"; S=1; }
done
[ "$S" = 0 ] && ok "cast plan metrics"

# AC4 the rule violations before and after, so a plan that removes one shows it
S=0
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [
  { "name": "ui-owns-nothing", "severity": "error", "from": "ui", "to": "logic",
    "kinds": ["value", "type", "dynamic"] },
  { "name": "no-back-edge", "severity": "error", "from": "logic", "to": "ui",
    "kinds": ["value"] }
] }
JSON
CAST_PV="$(cd "$CASTFIX" && "$CAST_BIN" plan simulate cut 2>&1)"
# break: evaluating the rules against one graph only
printf '%s\n' "$CAST_PV" | grep -q '^violations 4 -> 2' \
  || { fail "cast plan rules" "the violations were not counted before and after: $CAST_PV"; S=1; }
V_BEFORE="$(printf '%s\n' "$CAST_PV" | sed -n '/^violations /,$p' | sed -n '/^  before$/,/^  after$/p')"
V_AFTER="$(printf '%s\n' "$CAST_PV" | sed -n '/^violations /,$p' | sed -n '/^  after$/,$p')"
# the sites are under each rule, the same listing cast check gives
printf '%s\n' "$V_BEFORE" | grep -q 'src/a.ts:1 -> src/b.ts' \
  || { fail "cast plan rules" "the violations the project has today were not listed: $CAST_PV"; S=1; }
# a plan that removes a violation is visible as one that does
# break: listing the same violations under both headings
printf '%s\n' "$V_AFTER" | grep -q 'ui-owns-nothing' \
  && { fail "cast plan rules" "a violation the plan removes was still listed after it: $CAST_PV"; S=1; }
printf '%s\n' "$V_AFTER" | grep -q 'no-back-edge' \
  || { fail "cast plan rules" "a violation the plan adds was not listed after it: $CAST_PV"; S=1; }
[ "$S" = 0 ] && ok "cast plan rules"

# --- cast: the simulated graph, rendered ------------------------------------
# The same fixture and the same plan `cut`, drawn instead of counted. Every case
# here renders only: the fixture is never rescanned and never edited.

# AC1 --plan draws the graph cast plan simulate produces, not the scanned one,
# and without it both renderers draw the current graph exactly as they do today
S=0
CAST_RM_NOW="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid 2>&1)"; RC=$?
[ "$RC" = 0 ] || { fail "cast render plan" "cast render --mermaid exited $RC: $CAST_RM_NOW"; S=1; }
CAST_RM_PLAN="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid --plan cut 2>&1)"; RC=$?
# break: dying on --plan, or never accepting the flag at all
[ "$RC" = 0 ] || { fail "cast render plan" "cast render --mermaid --plan exited $RC: $CAST_RM_PLAN"; S=1; }
# the plan merges two modules of logic into one and moves a third out of it, so
# the layer the plan leaves holds four modules where the scanned one holds five
# break: ignoring --plan and rendering the scanned graph
printf '%s\n' "$CAST_RM_PLAN" | grep -qF 'logic (4)' \
  || { fail "cast render plan" "the mermaid render did not draw the graph the plan leaves: $CAST_RM_PLAN"; S=1; }
# break: rendering a plan whether or not one was asked for
printf '%s\n' "$CAST_RM_NOW" | grep -qF 'logic (5)' \
  || { fail "cast render plan" "the plain mermaid render did not draw the graph as scanned: $CAST_RM_NOW"; S=1; }
CAST_RH_PLAN="$CASTFIX/plan.html"
CAST_RH_NOW="$CASTFIX/now.html"
(cd "$CASTFIX" && "$CAST_BIN" render --html plan.html --plan cut >/dev/null 2>&1); RC=$?
[ "$RC" = 0 ] || { fail "cast render plan" "cast render --html --plan exited $RC"; S=1; }
(cd "$CASTFIX" && "$CAST_BIN" render --html now.html >/dev/null 2>&1) \
  || { fail "cast render plan" "cast render --html did not run"; S=1; }
# the merge names a module that exists in no scan of the fixture
# break: the page describing the scanned graph while mermaid describes the plan
grep -qF 'src/bc.ts' "$CAST_RH_PLAN" \
  || { fail "cast render plan" "the page did not draw the graph the plan leaves"; S=1; }
grep -qF 'src/bc.ts' "$CAST_RH_NOW" \
  && { fail "cast render plan" "the plain page drew the plan"; S=1; }

# AC2 rendering a plan writes no graph and no source file, and a plan that
# cannot be applied exits 2 having drawn nothing
rm -f "$CAST_RH_PLAN" "$CAST_RH_NOW"
CAST_RSUMS="$(cd "$CASTFIX" && find . -type f | sort | xargs cksum)"
CAST_RM2="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid --plan cut 2>&1)"; RC=$?
[ "$RC" = 0 ] || { fail "cast render plan" "the plan render exited $RC: $CAST_RM2"; S=1; }
# break: applying the plan to the loaded graph and writing it back to
# .cast/graph.json, or executing the moves against the source tree
[ "$CAST_RSUMS" = "$(cd "$CASTFIX" && find . -type f | sort | xargs cksum)" ] \
  || { fail "cast render plan" "rendering a plan changed the project"; S=1; }
# the page a plan render is asked for is the only file it writes
(cd "$CASTFIX" && "$CAST_BIN" render --html plan.html --plan cut >/dev/null 2>&1) \
  || { fail "cast render plan" "cast render --html --plan did not run"; S=1; }
CAST_RSUMS2="$(cd "$CASTFIX" && find . -type f ! -name plan.html | sort | xargs cksum)"
[ "$CAST_RSUMS" = "$CAST_RSUMS2" ] \
  || { fail "cast render plan" "rendering a plan to a page wrote more than the page"; S=1; }
rm -f "$CAST_RH_PLAN"
# a plan that cannot be applied stops the render: no such plan file
cat > "$CASTFIX/.cast/plans/broken.json" <<'JSON'
{ "operations": [ { "op": "move", "module": "src/gone.ts", "to": "pkg/gone.ts" } ] }
JSON
for bad in nope broken; do
  CAST_RBAD="$(cd "$CASTFIX" && "$CAST_BIN" render --html bad.html --plan $bad 2>&1)"; RC=$?
  # break: reading the plan after the page is written, or falling back to the
  # scanned graph when the plan cannot be applied
  [ "$RC" = 2 ] \
    || { fail "cast render plan" "an unapplicable plan $bad exited $RC, not 2: $CAST_RBAD"; S=1; }
  [ -e "$CASTFIX/bad.html" ] \
    && { fail "cast render plan" "an unapplicable plan $bad still drew a page"; S=1; }
  CAST_RBAD_M="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid --plan $bad 2>/dev/null)"; RC=$?
  [ "$RC" = 2 ] \
    || { fail "cast render plan" "an unapplicable plan $bad exited $RC from mermaid, not 2"; S=1; }
  [ -z "$CAST_RBAD_M" ] \
    || { fail "cast render plan" "an unapplicable plan $bad still drew a graph: $CAST_RBAD_M"; S=1; }
done
rm -f "$CASTFIX/.cast/plans/broken.json" "$CASTFIX/bad.html"
[ "$S" = 0 ] && ok "cast render plan"

# AC4 a count labelled edges counts the same thing everywhere: the report's is
# every import met, and every narrower count says it counts module edges
S=0
E_TOTAL="$(printf '%s\n' "$CAST_REPORT" | awk '/^edges /{print $2; exit}')"
# break: reporting the resolved edges under the same label the graph's every-edge
# count carries, which loses the unresolved and opaque ones without saying so
O="$(E_TOTAL="$E_TOTAL" graph '
  const all=g.modules.flatMap(m=>m.edges)
  if (all.length!==Number(process.env.E_TOTAL))
    bad("cast report says edges "+process.env.E_TOTAL+" of "+all.length+" edges in the graph")
')" || { fail "cast edge counts" "$O"; S=1; }
# the breakdown under it accounts for every one of them
# break: dropping a resolution from the breakdown, which hides a population
RES="$(printf '%s\n' "$CAST_REPORT" | sed -n '/^edges /{n;p;}' | tr ',' '\n')"
SUMRES="$(printf '%s\n' "$RES" | awk '{n+=$2} END{print n+0}')"
[ "$SUMRES" = "$E_TOTAL" ] \
  || { fail "cast edge counts" "$E_TOTAL edges break down into $SUMRES: $CAST_REPORT"; S=1; }
E_MOD="$(printf '%s\n' "$RES" | awk '$1=="module"{print $2}')"
[ -n "$E_MOD" ] && [ "$E_MOD" != "$E_TOTAL" ] \
  || { fail "cast edge counts" "the fixture cannot tell the two counts apart: $CAST_REPORT"; S=1; }
# the narrower counts carry the narrower label, and it is the same number
# break: labelling the module edges of one command `edges`, which makes two
# lines of one run disagree about what an edge is
printf '%s\n' "$CAST_PLAN" | awk '/^module edges /{print $3}' | grep -qx "$E_MOD" \
  || { fail "cast edge counts" "cast plan simulate started from another count than $E_MOD: $CAST_PLAN"; S=1; }
for o in "$CAST_PLAN" "$CAST_EDGES"; do
  printf '%s\n' "$o" | grep -q '^edges ' \
    && { fail "cast edge counts" "a count of module edges is labelled edges: $o"; S=1; }
  printf '%s\n' "$o" | grep -q '^module edges ' \
    || { fail "cast edge counts" "the count does not say which edges it counts: $o"; S=1; }
done
CAST_EC="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)" || true
printf '%s\n' "$CAST_EC" | grep -q 'module edges against' \
  || { fail "cast edge counts" "the check summary does not say which edges it read: $CAST_EC"; S=1; }
[ "$S" = 0 ] && ok "cast edge counts"

# --- cast: the page ----------------------------------------------------------
# The same scanned fixture, rendered to html with a rules file and a baseline in
# place. The suite runs on node alone, so what is asserted is the page's data,
# its tree, its layout numbers and its markup - never a browser.
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [
  { "name": "no-back-edge", "severity": "error", "from": "logic", "to": "ui", "kinds": ["value"] },
  { "name": "ui-owns-nothing", "severity": "warn", "from": "ui", "to": "logic", "kinds": ["value"] },
  { "name": "logic-internal", "severity": "warn", "from": "src/b.ts", "to": "src/c.ts" }
] }
JSON
cat > "$CAST_BASE" <<'JSON'
{ "violations": [ { "rule": "ui-owns-nothing", "file": "src/a.ts", "to": "src/b.ts", "kind": "value" } ] }
JSON
(cd "$CASTFIX" && "$CAST_BIN" render --html page.html >/dev/null 2>&1) \
  || { fail "cast html graph" "cast render --html did not run with rules in place"; }
CAST_PAGE="$CASTFIX/page.html"
# the embedded description, read out of the page and run through the very
# functions the page runs it through
page_data() { sed -n 's|^<script id="cast-data" type="application/json">\(.*\)</script>$|\1|p' "$CAST_PAGE"; }
CAST_DATA="$(page_data)"
# The keys are the containment path - the layer, then each folder level, then the
# file - and `treeId` is the only thing that turns one into a node id.
pagejs() { CAST_JS="$PWD/plugins/cast/scripts/cast.js" DATA="$CAST_DATA" PAGE="$CAST_PAGE" node -e '
  const bad=(s)=>{console.log(s);process.exit(1)}
  const cast=require(process.env.CAST_JS)
  const {treeId,treeOf,viewTree,layoutTree,marker,toggleOpen,groupIds,edgesAt,edgeLines}=cast
  const fs=require("fs")
  const page=fs.readFileSync(process.env.PAGE,"utf8")
  let data
  try { data=JSON.parse(process.env.DATA) } catch(e) { bad("the page carries no readable data block: "+e.message) }
  const view=(...open)=>viewTree(data,open.map(treeId))
  const at=(v,k)=>v.flat.find(n=>n.id===treeId(k))
  const edge=(v,f,t)=>v.edges.find(e=>e.from===treeId(f)&&e.to===treeId(t))
  const kids=(n)=>n.children.map(c=>c.label)
  '"$1"'
'; }

# AC6 (of #42) the page draws the graph itself - nodes, arrows and their weights -
# from the data in the file, and fetches nothing
S=0
[ -n "$CAST_DATA" ] \
  || { fail "cast html graph" "the page carries no embedded graph data"; S=1; }
# break: writing a page with the mermaid source and no canvas to draw on
grep -q '<svg id="graph"' "$CAST_PAGE" \
  || { fail "cast html graph" "the page has no svg to draw the graph in"; S=1; }
# break: embedding the layer names only, which leaves nothing to draw an arrow from
O="$(pagejs '
  const v=view()
  for (const n of ["ui (1)","logic (5)","unassigned (2)"])
    if (!v.nodes.map(x=>x.label).includes(n)) bad("the page data draws no node "+n)
  const e=edge(v,"ui","logic")
  if (!e) bad("the page data carries no ui -> logic arrow")
  if (e.weight!==3) bad("the ui -> logic arrow is weighted "+e.weight+", not 3")
  if (!edge(v,"logic","ui")) bad("the page data carries no logic -> ui arrow")
  const l=layoutTree(v)
  if (!(l.width>0&&l.height>0)) bad("the drawing has no extent: "+l.width+"x"+l.height)
  for (const n of l.flat) if (!Number.isFinite(n.x)||!Number.isFinite(n.y)) bad("the node "+n.label+" has no place")
  for (const e2 of l.edges) if (!Number.isFinite(e2.x1)||!Number.isFinite(e2.y2)) bad("an arrow has no endpoints")
')" || { fail "cast html graph" "$O"; S=1; }
# the page carries the code that draws it, and calls it
# break: embedding the data and no drawing code, which renders an empty svg
grep -q 'createElementNS' "$CAST_PAGE" \
  || { fail "cast html graph" "the page carries no code that draws svg"; S=1; }
grep -q '^draw()$' "$CAST_PAGE" \
  || { fail "cast html graph" "the page never calls its drawing code"; S=1; }
# the tree, the view and the layout in the page are the functions this suite
# tested, not a second set - break: writing the page's own copy, which drifts
O="$(pagejs '
  for (const f of [treeId,treeOf,viewTree,layoutTree])
    if (!page.includes(f.toString())) bad("the page does not carry the source of "+f.name)
')" || { fail "cast html graph" "$O"; S=1; }
# self-contained: it fetches nothing at view time
# break: pulling a layout or mermaid library off a cdn
grep -qE 'src="https?:|href="https?:|<script[^>]*src=|@import|url\(https?:' "$CAST_PAGE" \
  && { fail "cast html graph" "the page loads an asset over the network"; S=1; }
[ "$S" = 0 ] && ok "cast html graph"

# AC1 the graph carries a containment tree - layer, each folder level, then the
# file - and a node with children opens and closes at any depth
S=0
# break: keeping the two altitudes, a layer holding its modules with no folder
# between them
O="$(pagejs '
  const root=treeOf(data)
  if (root.children.map(n=>n.key).join(",")!=="ui,logic,unassigned")
    bad("the root does not hold one node per layer: "+root.children.map(n=>n.key))
  const ui=root.children[0]
  if (kids(ui).join(",")!=="src (1)") bad("the layer ui does not hold the folder src: "+kids(ui))
  if (ui.children[0].kind!=="folder") bad("a folder level is kind "+ui.children[0].kind)
  const f=ui.children[0].children[0]
  if (f.kind!=="file"||f.module!=="src/a.ts") bad("the leaf is not the file src/a.ts: "+f.kind+" "+f.module)
  if (f.label!=="a.ts") bad("the file node is labelled "+f.label)
  const logic=root.children[1]
  if (logic.children[0].children.length!==5) bad("the folder src of logic holds "+logic.children[0].children.length+" files, not 5")
  // every node knows the modules of its whole subtree - what an arrow and a
  // label are computed from
  if (logic.modules.length!==5) bad("the layer logic carries "+logic.modules.length+" modules in its subtree")
  if (root.children[2].children[0].key!=="unassigned/pkg") bad("the unassigned layer does not hold pkg")
')" || { fail "cast tree" "$O"; S=1; }
# a folder level below the first is a node too
# break: splitting the module id once and hanging the rest off the layer, which
# is a tree that stops at depth two whatever the project looks like
O="$(pagejs '
  const deep={layers:[{name:"core",modules:["src/x/y/z.ts","src/x/w.ts"]}],edges:[],counts:{}}
  const r=treeOf(deep)
  const path=[]
  let n=r.children[0]
  while (n) { path.push(n.key); n=n.children[0] }
  if (path.join(" > ")!=="core > core/src > core/src/x > core/src/x/y > core/src/x/y/z.ts")
    bad("the tree does not carry every folder level: "+path.join(" > "))
  const x=r.children[0].children[0].children[0]
  if (x.children.length!==2) bad("a folder holding a folder and a file holds "+x.children.length+" children")
')" || { fail "cast tree" "$O"; S=1; }
# opened and closed at any depth, through the ids the tree hands out
# break: an open state that is one layer name, which cannot name a folder
O="$(pagejs '
  const shut=view()
  if (shut.flat.length!==3) bad("with nothing open the page draws "+shut.flat.length+" nodes, not 3")
  const one=view("logic")
  if (!at(one,"logic").open) bad("opening the layer logic left it closed")
  if (!at(one,"logic/src")) bad("opening logic did not draw its folder src")
  if (at(one,"logic/src").open) bad("opening a layer opened the folder below it too")
  if (at(one,"logic/src/b.ts")) bad("a closed folder drew the files inside it")
  const two=view("logic","logic/src")
  if (!at(two,"logic/src").open) bad("the folder did not open at depth two")
  for (const m of ["b.ts","c.ts","t.ts","rel.ts","multi.ts"])
    if (!at(two,"logic/src/"+m)) bad("opening the folder did not draw its file "+m)
  if (at(two,"ui").open) bad("opening a node at depth opened another layer")
  const back=view("logic")
  if (at(back,"logic/src/b.ts")) bad("closing the folder left its files drawn")
  if (view().flat.length!==3) bad("closing the layer again did not restore the one box")
')" || { fail "cast tree" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast tree"

# AC2 an open node keeps its own outline and holds its children stacked inside
# it; a closed node is one box
S=0
# break: replacing an opened node with its children, the way --expand does, which
# loses the outline the reader opened
O="$(pagejs '
  const l=layoutTree(view("logic","logic/src"))
  const logic=at(l,"logic"), src=at(l,"logic/src"), b=at(l,"logic/src/b.ts")
  for (const n of [logic,src]) if (!n.open) bad("the opened node "+n.label+" is not drawn open")
  if (b.open) bad("a file node is drawn open")
  if (b.children.length) bad("a closed node holds children")
  if (at(l,"ui").h!==l.metrics.H) bad("a closed node is "+at(l,"ui").h+" tall, not the one box height")
  // the children sit inside the outline, at every depth
  const inside=(p,c)=>c.x>=p.x&&c.y>=p.y&&c.x+c.w<=p.x+p.w&&c.y+c.h<=p.y+p.h
  if (!inside(logic,src)) bad("the folder is not inside the layer that holds it")
  for (const c of src.children) if (!inside(src,c)) bad("the file "+c.label+" is not inside its folder")
  // stacked vertically inside it: one column, top to bottom, no overlap
  const col=src.children
  for (let i=1;i<col.length;i++) {
    if (col[i].x!==col[0].x) bad("the children are not one column: "+col[i].label+" is at x "+col[i].x)
    if (col[i].y<=col[i-1].y) bad("the children are not stacked top to bottom")
    if (col[i].y<col[i-1].y+col[i-1].h) bad("the child "+col[i].label+" overlaps the one above it")
  }
')" || { fail "cast nested layout" "$O"; S=1; }
# the page draws a node inside its parent and lets the inner one close itself
# break: handing every click to the outermost box, which makes a nested node
# unclickable
grep -q 'for (const c of n.children) box(c)' "$CAST_PAGE" \
  || { fail "cast nested layout" "the page does not draw the children of an open node"; S=1; }
grep -qF 'ev.stopPropagation(); toggle(n.id)' "$CAST_PAGE" \
  || { fail "cast nested layout" "a click on a nested node does not reach that node"; S=1; }
[ "$S" = 0 ] && ok "cast nested layout"

# AC3 an arrow runs between two closed nodes: where an endpoint is open, it is
# drawn from or to the closed descendant that carries the import
S=0
# break: aggregating an arrow onto the node the reader opened, which draws an
# arrow into a box and says nothing about which file inside it imports
O="$(pagejs '
  const open=["ui","ui/src","logic","logic/src"]
  const v=view(...open)
  const ids=new Set(v.flat.filter(n=>n.open).map(n=>n.id))
  for (const e of v.edges) {
    if (ids.has(e.from)) bad("an arrow leaves the open node "+e.from)
    if (ids.has(e.to)) bad("an arrow lands on the open node "+e.to)
  }
  for (const t of ["b.ts","t.ts","c.ts"]) {
    const e=edge(v,"ui/src/a.ts","logic/src/"+t)
    if (!e) bad("no arrow from the file that imports to the file src/"+t)
    if (e.weight!==1) bad("the arrow to src/"+t+" is weighted "+e.weight)
  }
  // an import inside one closed node has no arrow; opening that node draws it
  if (edge(view(),"logic","logic")) bad("a closed node was given an arrow to itself")
  const inner=edge(v,"logic/src/b.ts","logic/src/c.ts")
  if (!inner) bad("opening the folder did not draw the import inside it")
  // half open: the endpoint is the deepest closed node holding the import
  const half=view("logic")
  if (!edge(half,"ui","logic/src")) bad("with only the layer open the arrow does not reach the folder")
  if (edge(half,"ui","logic")) bad("an arrow still lands on the opened layer")
  if (edge(half,"ui","logic/src/b.ts")) bad("an arrow reaches into a closed folder")
')" || { fail "cast arrow endpoints" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast arrow endpoints"

# AC4 every arrow is labelled with the number of module imports behind it, and
# the arrows leaving a node sum to the imports leaving its subtree
S=0
# break: labelling an arrow 1, or dropping the sites it aggregates, which makes
# the number and what a click lists disagree
O="$(pagejs '
  const states=[[],["logic"],["logic","logic/src"],["ui","ui/src","logic","logic/src"],["unassigned","unassigned/pkg"]]
  for (const st of states) {
    const v=viewTree(data,st.map(treeId))
    const inside=new Map(v.flat.filter(n=>!n.open).flatMap(n=>n.modules.map(m=>[m,n.id])))
    for (const e of v.edges) {
      if (e.weight!==e.sites.length) bad("an arrow is weighted "+e.weight+" and carries "+e.sites.length+" imports")
      if (!e.label.startsWith(String(e.weight))) bad("the arrow is labelled "+e.label+", not by its weight "+e.weight)
    }
    for (const n of v.flat) {
      if (n.open) continue
      const out=v.edges.filter(e=>e.from===n.id).reduce((s,e)=>s+e.weight,0)
      const want=data.edges.filter(e=>inside.get(e.from)===n.id&&inside.get(e.to)!==n.id).length
      if (out!==want) bad("the arrows leaving "+n.key+" sum to "+out+", the imports leaving its subtree are "+want+" (open: "+st.join(",")+")")
    }
  }
')" || { fail "cast arrow counts" "$O"; S=1; }
# the count is of module imports, the number cast edges lists
# break: counting the modules that import instead of the imports
O="$(pagejs '
  const v=view()
  const e=edge(v,"ui","logic")
  const files=new Set(e.sites.map(s=>s.file))
  if (files.size===e.weight) bad("the fixture cannot tell an import count from a module count")
  if (e.weight!==3) bad("the ui -> logic arrow counts "+e.weight+" imports, not 3")
')" || { fail "cast arrow counts" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast arrow counts"

# AC5 the layout is vertical and stays compact: nodes stacked top to bottom, and
# a box only as tall as the children it shows
S=0
# break: sizing a box for the whole subtree, so a closed node is as tall as
# everything it hides and the page cannot be read
O="$(pagejs '
  const shut=layoutTree(view())
  const h=shut.flat.map(n=>n.h)
  if (new Set(h).size!==1) bad("closed nodes differ in height: "+h.join(","))
  if (h[0]!==shut.metrics.H) bad("a closed node is not one box high")
  // the top level is a column, top to bottom
  const top=shut.nodes
  for (let i=1;i<top.length;i++) {
    if (top[i].x!==top[0].x) bad("the top level is not one column")
    if (top[i].y<top[i-1].y+top[i-1].h) bad("the node "+top[i].label+" is not below the one before it")
  }
  // an open box is its header, its children and the padding - nothing for what
  // it does not show
  const M=shut.metrics
  const l=layoutTree(view("logic","logic/src","ui"))
  for (const n of l.flat) {
    if (!n.open) continue
    const want=M.HEAD+M.PAD+n.children.reduce((s,c)=>s+c.h,0)+M.GAP*(n.children.length-1)
    if (n.h!==want) bad("the open node "+n.key+" is "+n.h+" tall, the children it shows need "+want)
  }
  // opening a node grows the drawing by that node alone
  const one=layoutTree(view("ui"))
  const grew=one.height-shut.height
  if (grew<=0) bad("opening a node did not grow the drawing")
  const two=layoutTree(view("ui","ui/src"))
  if (two.height-one.height!==grew) bad("opening one file cost "+(two.height-one.height)+", opening one folder cost "+grew)
')" || { fail "cast compact layout" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast compact layout"

# AC6 an edge that breaks a rule is drawn in the colour of its severity and
# labelled with the rule, in the mermaid output and in the page alike; one held
# by the baseline is drawn as inherited. The mermaid view keeps its two levels.
S=0
CAST_MARK="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid 2>&1)"
# break: rendering without reading rules.json, which leaves every arrow the same
printf '%s\n' "$CAST_MARK" | grep -q '^  L_logic -->|1 no-back-edge| L_ui$' \
  || { fail "cast violation marks" "the breaking edge is not labelled with its rule: $CAST_MARK"; S=1; }
# break: labelling the rule but drawing every arrow in one colour
printf '%s\n' "$CAST_MARK" | grep -q '^  linkStyle 0 stroke:#d32f2f' \
  || { fail "cast violation marks" "the error edge is not drawn in the error colour: $CAST_MARK"; S=1; }
# break: reading the baseline nowhere but check, which draws inherited debt as new
printf '%s\n' "$CAST_MARK" | grep -q 'ui-owns-nothing (inherited)' \
  || { fail "cast violation marks" "a baselined edge is not drawn as inherited: $CAST_MARK"; S=1; }
printf '%s\n' "$CAST_MARK" | grep -q '^  linkStyle 1 stroke:#888' \
  || { fail "cast violation marks" "the inherited edge is not drawn as inherited: $CAST_MARK"; S=1; }
# the page says the same thing, off the same data
O="$(pagejs '
  const v=view()
  const bad1=edge(v,"logic","ui")
  if (bad1.state!=="breaking") bad("the page draws the breaking arrow as "+bad1.state)
  if (bad1.color!=="#d32f2f") bad("the breaking arrow is coloured "+bad1.color)
  if (bad1.label!=="1 no-back-edge") bad("the breaking arrow is labelled "+bad1.label)
  const held=edge(v,"ui","logic")
  if (held.state!=="inherited") bad("the page draws a baselined arrow as "+held.state)
  if (held.color!=="#888") bad("the inherited arrow is coloured "+held.color)
')" || { fail "cast violation marks" "$O"; S=1; }
printf '%s\n' "$CAST_DATA" | grep -q '"state":"inherited"' \
  || { fail "cast violation marks" "the page data marks no edge as inherited"; S=1; }
# drop the baseline and the same edge is breaking, at its own severity: the mark
# comes from the baseline, not from the rule
# break: hardcoding inherited, or colouring a warn the colour of an error
rm -f "$CAST_BASE"
CAST_MARK2="$(cd "$CASTFIX" && "$CAST_BIN" render --mermaid 2>&1)"
printf '%s\n' "$CAST_MARK2" | grep -q '(inherited)' \
  && { fail "cast violation marks" "an edge is inherited with no baseline: $CAST_MARK2"; S=1; }
printf '%s\n' "$CAST_MARK2" | grep -q '^  linkStyle 1 stroke:#e08b00' \
  || { fail "cast violation marks" "the warn edge is not drawn in the warn colour: $CAST_MARK2"; S=1; }
# break: giving the page the tree and letting the mermaid output follow it, which
# is the one view this change leaves alone
printf '%s\n' "$CAST_MARK2" | grep -q '^  L_ui\["ui (1)"\]$' \
  || { fail "cast violation marks" "the mermaid output no longer opens at layer altitude: $CAST_MARK2"; S=1; }
cat > "$CAST_BASE" <<'JSON'
{ "violations": [ { "rule": "ui-owns-nothing", "file": "src/a.ts", "to": "src/b.ts", "kind": "value" } ] }
JSON
[ "$S" = 0 ] && ok "cast violation marks"

# AC6 what #42 established holds at every depth: a click opens and closes, a
# click on an arrow lists the imports with file and line, a rule-breaking arrow
# keeps its mark and a baselined one reads as inherited, and every count the page
# shows equals what cast report and cast check print
S=0
# break: aggregating an arrow to a weight and dropping the imports behind it
O="$(pagejs '
  const e=edge(view(),"ui","logic")
  const want=["src/a.ts:1 -> src/b.ts (value)","src/a.ts:2 -> src/t.ts (type)","src/a.ts:6 -> src/c.ts (dynamic)"]
  const got=e.sites.map(s=>s.file+":"+s.line+" -> "+s.to+" ("+s.kind+")")
  for (const w of want) if (!got.includes(w)) bad("the arrow does not carry the site "+w+", only "+got.join(", "))
  if (got.length!==e.weight) bad("the arrow is weighted "+e.weight+" but carries "+got.length+" sites")
')" || { fail "cast html agrees" "$O"; S=1; }
# the same three, one level down - break: marking and siting an arrow at layer
# altitude only, which leaves an opened node drawing bare arrows
O="$(pagejs '
  const v=view("ui","ui/src","logic","logic/src")
  const held=edge(v,"ui/src/a.ts","logic/src/b.ts")
  if (!held) bad("no arrow between the two files at depth")
  if (held.state!=="inherited") bad("the baselined import reads as "+held.state+" at depth")
  const brk=edge(v,"logic/src/c.ts","ui/src/a.ts")
  if (brk.state!=="breaking"||brk.color!=="#d32f2f") bad("the breaking import is "+brk.state+" "+brk.color+" at depth")
  if (brk.sites[0].file!=="src/c.ts"||!Number.isFinite(brk.sites[0].line))
    bad("the arrow at depth carries no file and line: "+JSON.stringify(brk.sites[0]))
  // a violation inside one layer has no arrow until the layer is opened, and it
  // keeps its own severity when it appears
  const inner=edge(v,"logic/src/b.ts","logic/src/c.ts")
  if (inner.state!=="breaking"||inner.color!=="#e08b00") bad("the intra-layer violation is "+inner.state+" "+inner.color)
  if (inner.label!=="1 logic-internal") bad("the intra-layer arrow is labelled "+inner.label)
')" || { fail "cast html agrees" "$O"; S=1; }
# the sites are shown in the page itself, and a node and an arrow are clickable
# break: linking out to cast edges instead of listing them where the reader is
grep -q '<div id="sites">' "$CAST_PAGE" \
  || { fail "cast html agrees" "the page has nowhere to list the sites"; S=1; }
grep -qF "s.file + ':' + s.line" "$CAST_PAGE" \
  || { fail "cast html agrees" "the page does not render a site with its file and line"; S=1; }
grep -q "addEventListener('click', () => sites(e))" "$CAST_PAGE" \
  || { fail "cast html agrees" "an arrow in the page is not clickable"; S=1; }
# break: opening a node with no way back, which is a page with one state
grep -qF 'if (open[id] === true) delete open[id]' "$CAST_PAGE" \
  || { fail "cast html agrees" "a click on an open node does not close it again"; S=1; }
CAST_CHK="$(cd "$CASTFIX" && "$CAST_BIN" check 2>&1)" || true
C_SUM="$(printf '%s\n' "$CAST_CHK" | tail -1)"
n_of() { printf '%s\n' "$2" | sed -n "s/$1/\1/p" | head -1; }
li_of() { sed -n "s|^<li class=\"stat[^\"]*\"><span class=\"k\">$1</span><span class=\"v\">\([0-9]*\)</span></li>\$|\1|p" "$CAST_PAGE" | head -1; }
same() {
  [ -n "$2" ] || { fail "cast html agrees" "the command printed no $1 to compare"; S=1; return; }
  [ -n "$3" ] || { fail "cast html agrees" "the page shows no count for $1"; S=1; return; }
  [ "$2" = "$3" ] || { fail "cast html agrees" "the page says $1 $3, the commands say $2"; S=1; }
}
# break: counting the page's numbers off the drawn view, which drops the edges
# no arrow stands for, or hardcoding one of them
same modules "$(n_of '^modules \([0-9]*\)$' "$CAST_REPORT")" "$(li_of modules)"
same edges "$(n_of '^edges \([0-9]*\).*$' "$CAST_REPORT")" "$(li_of edges)"
same layers "$(n_of '^layers \([0-9]*\)$' "$CAST_REPORT")" "$(li_of layers)"
same unassigned "$(n_of '^unassigned \([0-9]*\)$' "$CAST_REPORT")" "$(li_of unassigned)"
same unresolved "$(n_of '^unresolved \([0-9]*\)$' "$CAST_REPORT")" "$(li_of unresolved)"
same opaque "$(n_of '^opaque \([0-9]*\)$' "$CAST_REPORT")" "$(li_of opaque)"
same cycles "$(n_of '^cycles \([0-9]*\)$' "$CAST_REPORT")" "$(li_of cycles)"
same violations "$(n_of '^\([0-9]*\) violation.*$' "$C_SUM")" "$(li_of violations)"
same errors "$(n_of '^.*(\([0-9]*\) error.*$' "$C_SUM")" "$(li_of errors)"
same 'module edges' "$(n_of '^.*in \([0-9]*\) module edge.*$' "$C_SUM")" "$(li_of 'module edges')"
same rules "$(n_of '^.*against \([0-9]*\) rule.*$' "$C_SUM")" "$(li_of rules)"
same baselined "$(n_of '^.*, \([0-9]*\) baselined$' "$C_SUM")" "$(li_of baselined)"
# every import the page draws an arrow for is one the commands counted
O="$(MODEDGES="$(li_of 'module edges')" pagejs '
  const drawn=view("ui","ui/src","logic","logic/src","unassigned","unassigned/pkg").edges
    .reduce((s,e)=>s+e.weight,0)
  if (drawn!==Number(process.env.MODEDGES))
    bad("the fully opened page draws "+drawn+" imports, the commands count "+process.env.MODEDGES)
')" || { fail "cast html agrees" "$O"; S=1; }
# the fixture has to be able to tell the two edge counts apart, or the suite
# would pass on a page that confused them
[ "$(li_of edges)" != "$(li_of 'module edges')" ] \
  || { fail "cast html agrees" "the fixture cannot tell edges from module edges"; S=1; }
[ "$(li_of violations)" != "$(li_of baselined)" ] || [ "$(li_of baselined)" = 0 ] \
  || { fail "cast html agrees" "the fixture cannot tell a live violation from a held one"; S=1; }
[ "$S" = 0 ] && ok "cast html agrees"
rm -f "$CAST_BASE"

# --- cast: an arrow a reader can follow --------------------------------------
# AC1/AC4 (of #46) every arrow shows which way the dependency runs, at every
# altitude. The head that used to say it is gone - on a page of many modules a
# head per arrow is what makes the drawing unreadable - and the side says it
# instead: an arrow to something further down the stack runs to the right of the
# boxes, one to something further up to the left of them.
S=0
# break: anchoring every arrow on the right, which draws the two directions the
# same way and leaves nothing on the page to tell them apart
O="$(pagejs '
  const states=[[],["logic"],["ui","ui/src","logic","logic/src"]]
  let down=0, up=0
  for (const st of states) {
    const l=layoutTree(viewTree(data,st.map(treeId)))
    if (!l.edges.length) bad("no arrow at all with "+st.join(",")+" open")
    for (const e of l.edges) {
      const a=l.flat.find(n=>n.id===e.from), b=l.flat.find(n=>n.id===e.to)
      const runsDown=b.y+b.h/2>=a.y+a.h/2
      if (e.down!==runsDown) bad("the arrow "+e.from+" -> "+e.to+" is drawn as if it ran the other way")
      if (runsDown) {
        down++
        if (e.x1!==a.x+a.w||e.x2!==b.x+b.w)
          bad("an arrow down the stack does not leave and arrive on the right of its boxes")
        if (!(e.mx>Math.max(e.x1,e.x2))) bad("an arrow down the stack does not run right of its boxes: mx "+e.mx)
      } else {
        up++
        if (e.x1!==a.x||e.x2!==b.x)
          bad("an arrow up the stack does not leave and arrive on the left of its boxes")
        if (!(e.mx<Math.min(e.x1,e.x2))) bad("an arrow up the stack does not run left of its boxes: mx "+e.mx)
      }
    }
  }
  // the fixture has to carry both directions, or the side proves nothing
  if (!down||!up) bad("the fixture draws "+down+" arrows down and "+up+" up")
  // break: leaving the left side of the drawing off the page, which clips every
  // arrow that runs up
  const l=layoutTree(view("ui","ui/src","logic","logic/src","unassigned","unassigned/pkg"))
  for (const e of l.edges) if (e.mx<0) bad("an arrow runs off the left of the drawing: mx "+e.mx)
  // break: keeping the marker per colour and state on the edge, which is the head
  // by another name
  for (const e of l.edges) if (e.marker!==undefined) bad("an arrow still carries a head: "+e.marker)
  if (l.markers!==undefined) bad("the drawing still defines arrowheads")
')" || { fail "cast arrow direction" "$O"; S=1; }
# break: drawing the curve with a marker-end again, which is the sprawl the side
# was meant to replace
grep -qF 'marker-end' "$CAST_PAGE" \
  && { fail "cast arrow direction" "the page still points an arrow with a head"; S=1; }
grep -qF "el('marker'" "$CAST_PAGE" \
  && { fail "cast arrow direction" "the page still defines a marker to point with"; S=1; }
# the direction is still there to be read in words, for the arrow a reader asks
# about - break: taking the side and saying nothing in its place
grep -qF "'imports ' : 'imported by '" "$CAST_PAGE" \
  || { fail "cast arrow direction" "the panel no longer says which way a dependency runs"; S=1; }
[ "$S" = 0 ] && ok "cast arrow direction"

# AC1 (of #47) the drawing at rest carries boxes and pointed lines and nothing
# else: no label box in the layout, no count on the page, and no extent a label
# sized. The suite `cast weight legible` tested where that label sat, and #47
# takes the label off the page, so it is replaced by this one and not dropped.
# AC2 (of #47) the edge still knows what it carries, as data
S=0
# break: keeping the label pass in layoutTree, which puts every box back
O="$(pagejs '
  const l=layoutTree(view("ui","ui/src","logic","logic/src","unassigned","unassigned/pkg"))
  const M=l.metrics
  if (l.edges.length<2) bad("the fixture has too few arrows to say anything about crowding")
  for (const e of l.edges) {
    for (const k of ["bx","by","bw","bh","hx","hy","hw","hh","lx","ly","ky"])
      if (e[k]!==undefined) bad("the arrow still carries the label geometry "+k+"="+e[k])
    // break: taking the data off the edge along with the drawing of it
    for (const k of ["weight","label","kinds","kindCounts","kindLabel","state","sites"])
      if (e[k]===undefined) bad("the arrow no longer carries "+k)
    if (!("rule" in e)) bad("the arrow no longer carries rule")
    if (e.weight!==e.sites.length) bad("the arrow is weighted "+e.weight+" and carries "+e.sites.length+" imports")
  }
  // break: sizing the drawing by a label box, which leaves the page wider and
  // taller than the arrows and the boxes on it
  const right=Math.max(...l.flat.map(n=>n.x+n.w))
  const out=Math.max(...l.edges.map(e=>e.mx))
  const low=Math.max(...l.flat.map(n=>n.y+n.h))
  if (l.width!==Math.max(right,out)+M.PAD)
    bad("the drawing is "+l.width+" wide, not the furthest arrow ("+out+") plus padding")
  if (l.height!==low+M.PAD)
    bad("the drawing is "+l.height+" tall, not the last box ("+low+") plus padding")
')" || { fail "cast arrows alone" "$O"; S=1; }
# break: leaving the second pass that draws the count over the lanes
grep -qF "class: 'weight'" "$CAST_PAGE" \
  && { fail "cast arrows alone" "the page still draws a count beside an arrow"; S=1; }
grep -qF "class: 'weight-bg'" "$CAST_PAGE" \
  && { fail "cast arrows alone" "the page still draws a backing for a count"; S=1; }
grep -qF "class: 'kinds'" "$CAST_PAGE" \
  && { fail "cast arrows alone" "the page still draws the kinds beside an arrow"; S=1; }
[ "$(grep -cF 'for (const e of l.edges) {' "$CAST_PAGE")" = 1 ] \
  || { fail "cast arrows alone" "the page still passes over the arrows twice, once for the labels"; S=1; }
# what the arrow carries is still there to be asked for
# break: dropping the press that lists the imports along with the label
grep -qF "line.addEventListener('click', () => sites(e))" "$CAST_PAGE" \
  || { fail "cast arrows alone" "a press on an arrow no longer lists its imports"; S=1; }
grep -qF "e.weight + ' module edges'" "$CAST_PAGE" \
  || { fail "cast arrows alone" "the list of imports is no longer headed by the count behind the arrow"; S=1; }
[ "$S" = 0 ] && ok "cast arrows alone"

# AC3 (of #47) the set of arrows a node answers for is computed from the laid-out
# edges, holds every arrow that starts or ends at the node and nothing else, and
# is empty for a node no arrow touches
S=0
# break: returning the outgoing arrows alone, or every arrow on the drawing
O="$(pagejs '
  const l=layoutTree(view("ui","ui/src","logic","logic/src","unassigned","unassigned/pkg"))
  const id=treeId("ui/src/a.ts")
  const mine=edgesAt(l.edges,id)
  if (mine.length===0) bad("the node answers for no arrow at all")
  if (mine.length===l.edges.length) bad("the node answers for every arrow on the drawing")
  if (!mine.some(e=>e.from===id)) bad("no arrow leaving the node is in its set")
  if (!mine.some(e=>e.to===id)) bad("no arrow arriving at the node is in its set")
  for (const e of mine) if (e.from!==id&&e.to!==id) bad("an arrow that misses the node is in its set")
  for (const e of l.edges)
    if ((e.from===id||e.to===id)&&mine.indexOf(e)<0) bad("an arrow touching the node is missing from its set")
  // break: answering a node no arrow touches with something
  const top=layoutTree(view())
  const lone=top.flat.find(n=>!top.edges.some(e=>e.from===n.id||e.to===n.id))
  if (!lone) bad("the fixture has no node without arrows")
  if (edgesAt(top.edges,lone.id).length!==0)
    bad("the node "+lone.label+" is touched by no arrow and answers for "+edgesAt(top.edges,lone.id).length)
  // computed, not read off a drawing: it answers before anything is drawn, and
  // the same twice - break: caching the last answer, or reaching for the DOM
  if (edgesAt(l.edges,id).length!==mine.length) bad("the set is not the same the second time it is asked for")
')" || { fail "cast highlight set" "$O"; S=1; }
# break: computing the set in the page from the svg it just drew
grep -qF 'function edgesAt(edges, id)' "$CAST_PAGE" \
  || { fail "cast highlight set" "the page does not carry the function that computes the set"; S=1; }
grep -qF 'edgesAt(laid.edges, id)' "$CAST_PAGE" \
  || { fail "cast highlight set" "the page does not highlight from the laid-out edges"; S=1; }
[ "$S" = 0 ] && ok "cast highlight set"

# AC4 (of #47) the panel names count, kinds, direction and rule per neighbour,
# one line each, and says so in one line where there is nothing to name
S=0
# break: printing the neighbours and dropping the count, the kinds or the way the
# dependency runs
O="$(pagejs '
  const l=layoutTree(view("ui","ui/src","logic","logic/src","unassigned","unassigned/pkg"))
  const id=treeId("ui/src/a.ts")
  const lines=edgeLines(l.edges,id)
  const mine=edgesAt(l.edges,id)
  if (lines.length!==mine.length) bad(lines.length+" lines for "+mine.length+" arrows")
  const out=lines.filter(s=>s.indexOf("imports ")===0)
  const back=lines.filter(s=>s.indexOf("imported by ")===0)
  if (out.length!==3||back.length!==1) bad("the directions read "+out.length+" out and "+back.length+" in, not 3 and 1")
  const t=lines.find(s=>s.indexOf("imports t.ts")===0)
  if (!t) bad("the type import neighbour is not named: "+lines.join(" | "))
  if (t.indexOf("1 module edges")<0) bad("the line does not say how many imports: "+t)
  if (t.indexOf("(1 type)")<0) bad("the line does not say which kinds and how many: "+t)
  const flagged=lines.find(s=>s.indexOf("imports b.ts")===0)
  if (flagged.indexOf("ui-owns-nothing")<0) bad("the line does not name the rule the edge holds: "+flagged)
  if (flagged.indexOf("(inherited)")<0) bad("the line does not say the rule is held by the baseline: "+flagged)
  const broken=lines.find(s=>s.indexOf("imported by c.ts")===0)
  if (broken.indexOf("no-back-edge")<0) bad("the line does not name the rule the edge breaks: "+broken)
  const plain=lines.find(s=>s.indexOf("imports c.ts")===0)
  if (/no-back-edge|ui-owns-nothing|logic-internal/.test(plain)) bad("an edge no rule names was given one: "+plain)
  // the kinds are counted, not listed - break: dropping the count of each kind
  const top=layoutTree(view())
  const ui=edgeLines(top.edges,treeId("ui")).find(s=>s.indexOf("imports logic")===0)
  if (ui.indexOf("3 module edges")<0) bad("the aggregated arrow does not carry its weight: "+ui)
  if (ui.indexOf("(1 value, 1 type, 1 dynamic)")<0) bad("the aggregated arrow does not count each kind: "+ui)
  // break: leaving a node no arrow touches with an empty panel
  const lone=top.flat.find(n=>!top.edges.some(e=>e.from===n.id||e.to===n.id))
  const none=edgeLines(top.edges,lone.id)
  if (none.length!==1) bad("a node with no arrows says it in "+none.length+" lines")
  if (!/no arrows/.test(none[0])) bad("a node with no arrows says: "+none[0])
')" || { fail "cast highlight info" "$O"; S=1; }
# break: keeping the lines out of the page, or building them in the drawing code
grep -qF 'function edgeLines(edges, id)' "$CAST_PAGE" \
  || { fail "cast highlight info" "the page does not carry the function that writes the lines"; S=1; }
grep -qF 'for (const line of edgeLines(laid.edges, id))' "$CAST_PAGE" \
  || { fail "cast highlight info" "the panel is not filled from those lines"; S=1; }
[ "$S" = 0 ] && ok "cast highlight info"

# AC5 (of #47) the highlight subtracts: every arrow outside the set is faded and
# every arrow inside it is left exactly as it is drawn at rest
S=0
# break: painting the highlighted arrows in a highlight colour, or thickening
# them, which restyles what it names instead of fading what it does not
HL="$(sed -n '/const highlight = (id, label) => {/,/^  const unhighlight/p' "$CAST_PAGE")"
[ -n "$HL" ] \
  || { fail "cast highlight dims" "the page carries no highlight"; S=1; }
printf '%s\n' "$HL" | grep -qF "toggle('dim', !mine.has(a.e))" \
  || { fail "cast highlight dims" "the highlight does not fade the arrows outside the set"; S=1; }
printf '%s\n' "$HL" | grep -qE "stroke|marker-end|fill|setAttribute" \
  && { fail "cast highlight dims" "the highlight restyles an arrow instead of only fading the others"; S=1; }
# break: fading with a rule that catches the boxes and the labels too
grep -qF '.edge.dim{opacity:' "$CAST_PAGE" \
  || { fail "cast highlight dims" "nothing on the page fades a dimmed arrow"; S=1; }
[ "$(grep -o '\.dim{' "$CAST_PAGE" | wc -l | tr -d ' ')" = 1 ] \
  || { fail "cast highlight dims" "more than the arrows is faded by the highlight"; S=1; }
grep -qE '\.node[^{]*\.dim|\.dim[^{]*\.node' "$CAST_PAGE" \
  && { fail "cast highlight dims" "a node is faded by the highlight"; S=1; }
[ "$S" = 0 ] && ok "cast highlight dims"

# AC6 (of #47) a mouse enters and leaves, and the binding is a mouse's alone: a
# touch screen fires pointerenter on first contact, so an unguarded binding
# highlights on every tap a phone makes
S=0
# break: binding pointerenter with no pointerType guard
grep -qF "head.addEventListener('pointerenter', (ev) => { if (ev.pointerType === 'mouse') highlight(n.id, n.label) })" "$CAST_PAGE" \
  || { fail "cast highlight mouse" "pointing at a node with a mouse does not highlight it, or is not bound for a mouse alone"; S=1; }
grep -qF "head.addEventListener('pointerleave', (ev) => { if (ev.pointerType === 'mouse') unhighlight() })" "$CAST_PAGE" \
  || { fail "cast highlight mouse" "leaving a node with a mouse does not clear the highlight, or is not bound for a mouse alone"; S=1; }
[ "$(grep -cF "addEventListener('pointerenter'" "$CAST_PAGE")" = 1 ] \
  || { fail "cast highlight mouse" "pointerenter is bound more than once, and one of them is unguarded"; S=1; }
[ "$S" = 0 ] && ok "cast highlight mouse"

# AC7 (of #47) a long press highlights on a touch screen and the click the
# release brings is eaten, so a press that highlights never also opens the group
S=0
# break: highlighting on pointerdown, which makes every tap highlight
grep -qF "if (ev.pointerType === 'mouse') return" "$CAST_PAGE" \
  || { fail "cast highlight touch" "the press is not held back from a mouse"; S=1; }
grep -qF "timer: setTimeout(() => { press = null; suppress = true; highlight(n.id, n.label) }, HOLD)" "$CAST_PAGE" \
  || { fail "cast highlight touch" "no timer turns a press into a highlight"; S=1; }
# break: leaving the click through, so the press that highlights also toggles
grep -qF "if (suppress) { suppress = false; ev.stopPropagation(); return }" "$CAST_PAGE" \
  || { fail "cast highlight touch" "the click after a press that highlighted still opens the group"; S=1; }
# break: letting a scroll or a release count as a press
grep -qF "if (press && (Math.abs(ev.clientX - press.x) > SLOP || Math.abs(ev.clientY - press.y) > SLOP)) cancelPress()" "$CAST_PAGE" \
  || { fail "cast highlight touch" "a move beyond the slop does not cancel the press"; S=1; }
grep -qF "head.addEventListener('pointerup', (ev) => { if (ev.pointerType !== 'mouse') cancelPress() })" "$CAST_PAGE" \
  || { fail "cast highlight touch" "a release does not cancel the press"; S=1; }
grep -qF "head.addEventListener('pointercancel', (ev) => { if (ev.pointerType !== 'mouse') cancelPress() })" "$CAST_PAGE" \
  || { fail "cast highlight touch" "a cancelled press is left running"; S=1; }
# break: clearing the highlight on the release, which takes the numbers away in
# the moment the finger lifts and leaves a phone no way to read them
grep -qE "pointer(up|cancel)', \(ev\) => \{ if \(ev.pointerType !== 'mouse'\) \{ cancelPress\(\); unhighlight" "$CAST_PAGE" \
  && { fail "cast highlight touch" "lifting the finger clears the highlight the press asked for"; S=1; }
[ "$S" = 0 ] && ok "cast highlight touch"

# AC8 (of #47) the highlight ends: on leaving with the mouse, on a tap
# elsewhere, and on the render that opening or closing a group brings. Not on the
# release of the long press - the finger lifts and the numbers stay readable -
# and not on a scroll: the touch that scrolls the page is how a phone reaches the
# panel the highlight wrote.
S=0
# break: fading the arrows and never restoring them, or leaving the panel full
O="$(pagejs '
  const un=page.slice(page.indexOf("const unhighlight = () => {"))
  const body=un.slice(0,un.indexOf("\n  }")+4)
  if (!body) bad("the page carries no way back from a highlight")
  if (body.indexOf("classList.remove(\x27dim\x27)")<0) bad("clearing the highlight does not restore the faded arrows")
  if (body.indexOf("panel.textContent = \x27\x27")<0) bad("clearing the highlight does not empty the panel")
  if (body.indexOf("held = null")<0) bad("clearing the highlight leaves the node held")
')" || { fail "cast highlight ends" "$O"; S=1; }
# break: pressing elsewhere on a phone, where no pointer leaves, leaves the
# drawing faded with no way back
grep -qF "document.addEventListener('pointerdown', (ev) => {" "$CAST_PAGE" \
  || { fail "cast highlight ends" "a press away from the highlighted node never clears it"; S=1; }
grep -qF "away = (!g || g.id !== held) ? { x: ev.clientX, y: ev.clientY, held } : null" "$CAST_PAGE" \
  || { fail "cast highlight ends" "a press away from the highlighted node does not propose the end"; S=1; }
# break: clearing on the release whatever the highlight is now, so a long press
# on a second node highlights it and its own release takes it straight away again
grep -qF "if (away && away.held === held) unhighlight()" "$CAST_PAGE" \
  || { fail "cast highlight ends" "the release of a press away from the highlighted node does not clear it"; S=1; }
# the touch that begins a scroll must not clear anything: the reader scrolls to
# read the panel the highlight wrote
# break: calling unhighlight() from the document pointerdown, which wipes the
# highlight in the moment the finger touches down to scroll
AW="$(sed -n "/^  document.addEventListener('pointerdown', (ev) => {/,/^  })/p" "$CAST_PAGE")"
printf '%s\n' "$AW" | grep -qF 'unhighlight()' \
  && { fail "cast highlight ends" "the touch that starts a scroll clears the highlight before it is a tap"; S=1; }
# break: taking the release for a tap wherever it lands, so a scroll that ends
# off the node clears the highlight it scrolled to read
grep -qF "if (away && (Math.abs(ev.clientX - away.x) > SLOP || Math.abs(ev.clientY - away.y) > SLOP)) cancelAway()" "$CAST_PAGE" \
  || { fail "cast highlight ends" "a gesture that travels still counts as the tap that dismisses"; S=1; }
# break: leaving the proposal standing when the browser takes the gesture over
# for a scroll, so the next release elsewhere clears a highlight nobody dismissed
grep -qF "document.addEventListener('pointercancel', cancelAway)" "$CAST_PAGE" \
  || { fail "cast highlight ends" "a cancelled gesture leaves the dismissal standing"; S=1; }
# break: rebuilding the drawing and leaving the old highlight state behind
RB="$(sed -n '/^  function render() {/,/^    svg.textContent/p' "$CAST_PAGE")"
printf '%s\n' "$RB" | grep -qF 'unhighlight()' \
  || { fail "cast highlight ends" "a render does not clear the highlight it started with"; S=1; }
printf '%s\n' "$RB" | grep -qF 'arrows = []' \
  || { fail "cast highlight ends" "a render does not start the set of arrows again"; S=1; }
[ "$S" = 0 ] && ok "cast highlight ends"

# AC3 (of #46) an arrow carries the kinds of the imports behind it, so an edge a
# rule's `kinds` spares reads differently from one no rule names.
S=0
# break: aggregating an arrow to a weight and a rule and dropping the kinds
O="$(pagejs '
  const e=edge(view(),"ui","logic")
  if (!e.kinds) bad("the arrow carries no kinds")
  if (e.kinds.join(",")!=="value,type,dynamic") bad("the arrow carries the kinds "+e.kinds.join(","))
  const counted=e.kinds.reduce((s,k)=>s+e.kindCounts[k],0)
  if (counted!==e.weight) bad("the kinds count "+counted+" imports, the arrow is weighted "+e.weight)
  if (!e.kindLabel.includes("1 type")) bad("the arrow does not say how many of each kind: "+e.kindLabel)
  // the rule flags value imports alone: the type and the dynamic import beside
  // it are spared, and the kinds are what says so
  const d=view("ui","ui/src","logic","logic/src")
  const spared=edge(d,"ui/src/a.ts","logic/src/t.ts")
  const flagged=edge(d,"ui/src/a.ts","logic/src/b.ts")
  if (spared.kinds.join(",")!=="type") bad("the type import reads as "+spared.kinds.join(","))
  if (spared.state) bad("the type import a kinds rule spares is drawn as "+spared.state)
  if (!flagged.state) bad("the value import the rule names is drawn as unmarked")
  const other=edge(d,"ui/src/a.ts","logic/src/c.ts")
  if (other.kindLabel===spared.kindLabel)
    bad("an import the rule spares reads the same as one it does not name: "+other.kindLabel)
')" || { fail "cast arrow kinds" "$O"; S=1; }
# break: keeping the kinds in the data and never showing them. #47 took the
# kinds off the drawing, so the panel is where they are read now: the press on an
# arrow heads its imports with them, and the highlight names them per neighbour.
grep -qF "(e.kindLabel ? ' (' + e.kindLabel + ')' : '')" "$CAST_PAGE" \
  || { fail "cast arrow kinds" "the page never shows the kinds of an arrow"; S=1; }
grep -qF "e.kindLabel ? ' (' + e.kindLabel + ')' : ''" "$CAST_PAGE" \
  || { fail "cast arrow kinds" "the list of imports is not headed by the kinds behind the arrow"; S=1; }
printf '%s\n' "$CAST_DATA" | grep -q '"kind":"type"' \
  || { fail "cast arrow kinds" "the fixture has no type import to spare"; S=1; }
[ "$S" = 0 ] && ok "cast arrow kinds"


# --- cast: the controls that close a group -----------------------------------
# The same page, read for what a reader can see and press. Still node alone: the
# markup, the css, the layout numbers and the pure functions the page toggles
# with are what these assert - never a browser and never a device.

# AC1 a node that has children carries a visible open/closed marker in its own
# header, and a node without children carries none
S=0
# break: drawing one glyph for both states, or drawing a marker on a file, which
# tells the reader a leaf is a group and leaves a group looking like a leaf
O="$(pagejs '
  const v=view("logic","logic/src")
  const openg=at(v,"logic"), file=at(v,"logic/src/b.ts"), shut=at(view(),"logic")
  if (openg.hasChildren!==true) bad("an opened group is not marked as having children")
  if (at(view(),"logic").hasChildren!==true) bad("a closed group forgets it has children")
  if (file.hasChildren!==false) bad("the file node b.ts claims children")
  if (!marker(shut)) bad("a closed group carries no marker")
  if (!marker(openg)) bad("an open group carries no marker")
  if (marker(shut)===marker(openg)) bad("open and closed carry the same marker "+marker(shut))
  if (marker(file)!=="") bad("a node without children carries the marker "+marker(file))
')" || { fail "cast group marker" "$O"; S=1; }
# the marker is drawn, in the header, and only where there is one
# break: computing the marker and never putting it on the page
grep -qF 'const m = marker(n)' "$CAST_PAGE" \
  || { fail "cast group marker" "the page draws no marker for a node"; S=1; }
grep -qF "if (m) head.appendChild(el('text'" "$CAST_PAGE" \
  || { fail "cast group marker" "the marker is not drawn into the node's header"; S=1; }
# break: hiding the marker behind :hover, which no phone can produce
grep -qF ':hover' "$CAST_PAGE" \
  && { fail "cast group marker" "the page puts something behind :hover, which a touch screen cannot reach"; S=1; }
[ "$S" = 0 ] && ok "cast group marker"

# AC2 opening and closing happens on the header - its marker and its label - and
# not on the rest of the box
S=0
# break: sizing the header to the whole box, so a press anywhere inside an open
# group collapses it
O="$(pagejs '
  const l=layoutTree(view("logic","logic/src"))
  const M=l.metrics
  const g=at(l,"logic")
  if (g.hx!==g.x||g.hy!==g.y) bad("the header does not sit at the top left of the node")
  if (g.hw!==g.w) bad("the header is "+g.hw+" wide, the node is "+g.w)
  if (g.hh!==M.HEAD) bad("the header of an open node is "+g.hh+" high, not the header height "+M.HEAD)
  if (!(g.h>g.hh)) bad("the open node is all header: there is no area a press does nothing in")
  for (const c of g.children)
    if (c.y<g.hy+g.hh) bad("the child "+c.key+" sits inside its parent header")
  // a closed node has no ground of its own: the box is the header
  const ui=at(l,"ui")
  if (ui.hh!==ui.h) bad("a closed node is "+ui.h+" high and its header "+ui.hh)
')" || { fail "cast group control" "$O"; S=1; }
# break: leaving the click on the node group, which is the whole box again
grep -qF "head.addEventListener('click'" "$CAST_PAGE" \
  || { fail "cast group control" "the header does not toggle the node"; S=1; }
grep -qF "g.addEventListener('click'" "$CAST_PAGE" \
  && { fail "cast group control" "the whole node box still toggles"; S=1; }
# break: toggling a node that has nothing to open, which is a press with no answer
grep -qF 'if (n.hasChildren) {' "$CAST_PAGE" \
  || { fail "cast group control" "a node without children is given the toggle too"; S=1; }
# break: dropping stopPropagation, so one press closes the node and its ancestor
grep -qF 'ev.stopPropagation()' "$CAST_PAGE" \
  || { fail "cast group control" "a press on an inner header reaches the ancestor too"; S=1; }
[ "$S" = 0 ] && ok "cast group control"

# AC3 one control closes every group at once, one opens every group that has
# children
S=0
# break: offering only the layers, which leaves a reader who opened three levels
# with two of them still open
O="$(pagejs '
  const ids=groupIds(data)
  for (const k of ["ui","logic","unassigned","ui/src","logic/src","unassigned/pkg"])
    if (!ids.includes(treeId(k))) bad("open all does not open the group "+k)
  for (const k of ["logic/src/b.ts","ui/src/a.ts"])
    if (ids.includes(treeId(k))) bad("open all offers to open "+k+", which has nothing inside it")
  const all=viewTree(data,ids)
  for (const id of ids) {
    const n=all.flat.find(x=>x.id===id)
    if (!n) bad("a group open all names is not drawn")
    if (!n.open) bad("the group "+n.key+" is not open after open all")
  }
  if (all.flat.filter(n=>!n.open).length===0) bad("nothing is left closed, so the fixture proves nothing")
  // close all is the empty state, and it is reachable from any other
  const shut=viewTree(data,[])
  if (shut.flat.length!==3) bad("closing every group leaves "+shut.flat.length+" nodes, not the 3 layers")
  if (shut.flat.some(n=>n.open)) bad("a group is still open after close all")
')" || { fail "cast collapse all" "$O"; S=1; }
# the controls are on the page and wired to that state
# break: writing the two buttons and leaving them inert
grep -q 'id="collapse-all"' "$CAST_PAGE" \
  || { fail "cast collapse all" "the page carries no control that closes every group"; S=1; }
grep -q 'id="expand-all"' "$CAST_PAGE" \
  || { fail "cast collapse all" "the page carries no control that opens every group"; S=1; }
grep -qF "getElementById('collapse-all').addEventListener('click', () => setAll([]))" "$CAST_PAGE" \
  || { fail "cast collapse all" "the close-all control is not wired to the empty state"; S=1; }
grep -qF "getElementById('expand-all').addEventListener('click', () => setAll(groupIds(data)))" "$CAST_PAGE" \
  || { fail "cast collapse all" "the open-all control is not wired to every group"; S=1; }
[ "$S" = 0 ] && ok "cast collapse all"

# AC4 closing a group closes it alone: its descendants keep the state they had
S=0
# break: clearing the ids below the one closed - the page looks the same until
# the group is opened again, and then everything inside it is shut
O="$(pagejs '
  const L=treeId("logic"), SRC=treeId("logic/src"), UI=treeId("ui")
  const open={}
  for (const id of [UI,L,SRC]) toggleOpen(open,id)
  toggleOpen(open,L)
  if (open[L]) bad("closing the group left it open")
  if (open[SRC]!==true) bad("closing a group forgot that the folder inside it was open")
  if (open[UI]!==true) bad("closing a group closed a sibling")
  const half=viewTree(data,Object.keys(open))
  if (at(half,"logic/src")) bad("the closed group still draws what was inside it")
  toggleOpen(open,L)
  const back=viewTree(data,Object.keys(open))
  if (!at(back,"logic").open) bad("opening the group again left it closed")
  if (!at(back,"logic/src").open) bad("reopening the group did not restore the folder that was open")
  if (!at(back,"logic/src/b.ts")) bad("reopening the group shows a collapsed subtree, not what was open before")
')" || { fail "cast collapse state" "$O"; S=1; }
# break: giving the page its own toggle beside the tested one, which drifts
grep -qF 'toggleOpen(open, id)' "$CAST_PAGE" \
  || { fail "cast collapse state" "the page does not toggle through toggleOpen"; S=1; }
[ "$S" = 0 ] && ok "cast collapse state"

# AC5 the page declares a viewport, so a phone lays it out at device width
S=0
# break: leaving the meta out, which lays the page out at a desktop width and
# scales it down until every target and every label is a third of its size
grep -qF '<meta name="viewport" content="width=device-width, initial-scale=1">' "$CAST_PAGE" \
  || { fail "cast viewport" "the page declares no viewport at device width"; S=1; }
# break: locking the scale, which is the same page with pinch zoom taken away
grep -qE 'user-scalable=no|maximum-scale=1' "$CAST_PAGE" \
  && { fail "cast viewport" "the page forbids the reader to zoom"; S=1; }
[ "$S" = 0 ] && ok "cast viewport"

# AC6 every control offers at least 44 css pixels in both directions, and a
# single press acts once
S=0
# break: keeping the desktop metrics - a 24 pixel header and a 22 pixel lane,
# which is a target a finger misses
O="$(pagejs '
  const TAP=44
  const l=layoutTree(view("logic","logic/src","ui","ui/src"))
  const M=l.metrics
  if (M.TAP!==TAP) bad("the layout does not carry the 44 pixel target size: TAP is "+M.TAP)
  for (const k of ["H","HEAD"])
    if (M[k]<TAP) bad("the metric "+k+" is "+M[k]+", below the "+TAP+" pixel target")
  for (const n of l.flat) {
    if (n.hh<TAP) bad("the header of "+n.key+" is "+n.hh+" high, below "+TAP)
    if (n.hw<TAP) bad("the header of "+n.key+" is "+n.hw+" wide, below "+TAP)
  }
  // Arrows reserve no lane since #48, so nothing keeps two of them a press apart
  // any more: where two run over the same stretch the press lands on the one
  // drawn last. That is the price of a flat curve and it is not tested here -
  // what a press has to hit is the target over the curve, checked below.
')" || { fail "cast touch targets" "$O"; S=1; }
# break: leaving the html controls at the browser default, ~20 pixels high
grep -qF 'button{font:inherit;min-height:44px;min-width:44px' "$CAST_PAGE" \
  || { fail "cast touch targets" "the page's own controls carry no 44 pixel minimum"; S=1; }
# break: dropping touch-action, so a phone holds every press back to see whether
# a second one is coming and zooms instead
grep -qF 'touch-action:manipulation' "$CAST_PAGE" \
  || { fail "cast touch targets" "the page never declares touch-action, so a press can become a zoom"; S=1; }
# break: drawing the target and never letting it take the press
grep -qF '.hit,.node .hit{fill:transparent;pointer-events:all}' "$CAST_PAGE" \
  || { fail "cast touch targets" "the invisible targets take no press"; S=1; }
grep -qF "class: 'edge grab'" "$CAST_PAGE" \
  || { fail "cast touch targets" "an arrow is only as wide as the line drawn for it"; S=1; }
# break: narrowing that target to the stroke of the line, which two arrows over
# one stretch now leave a finger no way to hit at all
grep -qF "'stroke-width': M.TAP, class: 'edge grab'" "$CAST_PAGE" \
  || { fail "cast touch targets" "the target over an arrow is not a finger wide"; S=1; }
[ "$S" = 0 ] && ok "cast touch targets"

# AC7 on a narrow screen the graph scrolls inside its own container instead of
# shrinking, and the body never scrolls sideways
S=0
# break: svg{max-width:100%;height:auto}, which fits a deep tree to a phone by
# shrinking it until nothing on it can be read or pressed
grep -qE 'svg\{[^}]*max-width:100%' "$CAST_PAGE" \
  && { fail "cast narrow screen" "the graph is still scaled down to fit the screen"; S=1; }
grep -qF '<div id="graph-scroll">' "$CAST_PAGE" \
  || { fail "cast narrow screen" "the graph has no container of its own to scroll in"; S=1; }
grep -qF '#graph-scroll{overflow-x:auto;max-width:100%' "$CAST_PAGE" \
  || { fail "cast narrow screen" "the graph container does not scroll sideways within the screen"; S=1; }
# break: leaving the svg without a size, so the container has nothing to scroll
grep -qF "svg.setAttribute('width', l.width)" "$CAST_PAGE" \
  || { fail "cast narrow screen" "the drawing does not keep its own width"; S=1; }
grep -qF "svg.setAttribute('height', l.height)" "$CAST_PAGE" \
  || { fail "cast narrow screen" "the drawing does not keep its own height"; S=1; }
# break: letting the page itself scroll sideways, which moves the text away from
# the reader every time they scroll the graph
grep -qF 'html,body{max-width:100%;overflow-x:hidden}' "$CAST_PAGE" \
  || { fail "cast narrow screen" "the page body can scroll sideways"; S=1; }
[ "$S" = 0 ] && ok "cast narrow screen"


# --- cast skills ------------------------------------------------------------
# The three skills a session reaches cast through. Each one runs its wrapper in
# the prompt, so the model never has to know the flags - a skill that only
# describes the command is the failure these exist to prevent.
S=0
for s in map plan; do
  F="plugins/cast/skills/$s/SKILL.md"
  if [ ! -f "$F" ]; then fail "cast skills" "$F is missing"; S=1; continue; fi
  # break: dropping allowed-tools, which hands the skill the whole tool surface
  # instead of the two tools it reads its answer with.
  FM="$(sed -n '2,/^---$/p' "$F")"
  for k in name description allowed-tools; do
    printf '%s\n' "$FM" | grep -q "^$k:" \
      || { fail "cast skills" "$F carries no $k in its frontmatter"; S=1; }
  done
  # break: copying the skill body's name from another skill
  printf '%s\n' "$FM" | grep -qx "name: $s" \
    || { fail "cast skills" "$F does not name itself $s"; S=1; }
  # break: copying the skill into .claude/skills, where an edit to the source in
  # plugins/cast is not live in the session.
  [ -L ".claude/skills/$s" ] \
    || { fail "cast skills" ".claude/skills/$s is not a symbolic link"; S=1; }
  [ "$(readlink -f ".claude/skills/$s")" = "$PWD/plugins/cast/skills/$s" ] \
    || { fail "cast skills" ".claude/skills/$s does not point at plugins/cast/skills/$s"; S=1; }
done
# break: writing the wrapper as prose, or in a fenced block, instead of a `!`
# line the prompt expansion executes before the model reads it.
skill_runs() {
  F="plugins/cast/skills/$1/SKILL.md"
  [ -f "$F" ] || return 0
  grep '^!' "$F" | grep -q -- "$2" \
    || { fail "cast skills" "$F does not run '$2' in the prompt"; S=1; }
}
skill_runs map 'report'
# The plan skill simulates a plan it has not drafted yet, so the prompt line
# reports the graph it drafts against; `plan simulate` is run per loop, and the
# `cast plan skill` suite below is what holds it there.
skill_runs plan 'report'
[ "$S" = 0 ] && ok "cast skills"


# --- cast skill root --------------------------------------------------------
# AC6 every skill takes an optional target directory and runs cast against it.
# The prompt line resolves that root once, echoes it so the model can pass it on,
# and carries it on every call it makes - with no argument, the working directory.
S=0
for s in map plan; do
  F="plugins/cast/skills/$s/SKILL.md"
  [ -f "$F" ] || { fail "cast skill root" "$F is missing"; S=1; continue; }
  L="$(grep '^!' "$F" | head -1)"
  # break: dropping --root from one of the calls on the line, so the scan reads
  # the working directory and the command reads the directory that was asked for
  C="$(printf '%s\n' "$L" | grep -o '"\$CAST"' | wc -l | tr -d ' ')"
  R="$(printf '%s\n' "$L" | grep -o -- '--root "\$R"' | wc -l | tr -d ' ')"
  [ "$C" -ge 2 ] || { fail "cast skill root" "$F runs fewer than two cast calls in its prompt"; S=1; }
  [ "$C" = "$R" ] || { fail "cast skill root" "$F makes $C cast calls but passes --root on $R of them"; S=1; }
  # break: leaving the root empty when no argument is given, which is a usage
  # error instead of a run against the working directory
  printf '%s\n' "$L" | grep -q 'R=\.' \
    || { fail "cast skill root" "$F does not fall back to the working directory"; S=1; }
  # break: resolving the root and never telling the model, so every command it
  # runs afterwards answers about a different project
  printf '%s\n' "$L" | grep -q 'echo "cast root: \$R"' \
    || { fail "cast skill root" "$F never reports the root it resolved"; S=1; }
  # break: documenting the argument as the plan name or the rule alone, so the
  # directory is never passed
  grep -q 'working directory' "$F" \
    || { fail "cast skill root" "$F does not say what happens without a directory"; S=1; }
  # break: telling the model the root and not that its own calls need it
  grep -qF -- '--root <root>' "$F" \
    || { fail "cast skill root" "$F never asks for --root <root> on the calls it hands on"; S=1; }
done
# break: the skill whose argument is not the directory taking the trailing word
# blindly, so a goal is read as a root
F="plugins/cast/skills/plan/SKILL.md"
if [ -f "$F" ]; then
  grep '^!' "$F" | grep -qF '[ -d "$L" ]' \
    || { fail "cast skill root" "$F takes its trailing word as a root without testing it is a directory"; S=1; }
fi
# The line is run, not read: the argument is the directory that was asked about,
# and the whole complaint the guard answers is a map of the whole project handed
# back to someone who asked about one subdirectory.
CAST_REPO="$PWD"
map_line() {
  ARGS="$1" CASTFIX="$CASTFIX" CAST_REPO="$CAST_REPO" bash -c '
    cd "$CASTFIX" || exit 1
    export CLAUDE_PLUGIN_ROOT="$CAST_REPO/plugins/cast"
    ARGUMENTS="$ARGS"
    '"$(grep '^!' plugins/cast/skills/map/SKILL.md | head -1 | sed -e 's/^!`//' -e 's/`$//')"'
  ' 2>&1
}
# break: reading the argument and scanning the working directory anyway
CAST_ML_SUB="$(map_line src)"
printf '%s\n' "$CAST_ML_SUB" | grep -qx 'cast root: src' \
  || { fail "cast skill root" "the map line did not resolve the directory it was given: $CAST_ML_SUB"; S=1; }
printf '%s\n' "$CAST_ML_SUB" | grep -q '^modules ' \
  || { fail "cast skill root" "the map line reported no graph for the directory it was given: $CAST_ML_SUB"; S=1; }
printf '%s\n' "$CAST_ML_SUB" | grep -qF 'pkg/one.toy' \
  && { fail "cast skill root" "a map of src reported a module outside src"; S=1; }
# break: falling back to the working directory when the argument names no
# directory - the whole project answered where one directory was asked for, and
# nothing in the answer says so
CAST_ML_BAD="$(map_line 'the src folder')"
printf '%s\n' "$CAST_ML_BAD" | grep -q '^cast root: none' \
  || { fail "cast skill root" "an argument that is no directory did not report cast root: none: $CAST_ML_BAD"; S=1; }
printf '%s\n' "$CAST_ML_BAD" | grep -q '^modules ' \
  && { fail "cast skill root" "an argument that is no directory was mapped as the whole project anyway"; S=1; }
grep -qF 'cast root: none' plugins/cast/skills/map/SKILL.md \
  || { fail "cast skill root" "the map skill never says what cast root: none means"; S=1; }
# break: no argument at all is still the working directory
CAST_ML_NONE="$(map_line '')"
printf '%s\n' "$CAST_ML_NONE" | grep -qx 'cast root: .' \
  || { fail "cast skill root" "the map line without an argument did not fall back to the working directory: $CAST_ML_NONE"; S=1; }
[ "$S" = 0 ] && ok "cast skill root"


# --- cast agents ------------------------------------------------------------
# The two subagents a session delegates the graph to. Each is a context boundary
# around a skill that already exists, and what it buys is the report, the edge
# listings and the rounds of simulation staying out of the caller - so a
# definition that hands those back anyway has paid a dispatch for nothing.
S=0
for a in graph-analyst refactor-planner; do
  F="plugins/cast/agents/$a.md"
  if [ ! -f "$F" ]; then fail "cast agents" "$F is missing"; S=1; continue; fi
  FM="$(sed -n '2,/^---$/p' "$F")"
  # break: dropping description, which is the only thing routing reads - an
  # agent nothing routes to is never dispatched and the session runs cast itself
  for k in name description model tools skills; do
    printf '%s\n' "$FM" | grep -q "^$k:" \
      || { fail "cast agents" "$F carries no $k in its frontmatter"; S=1; }
  done
  # break: copying one agent's file to the other and leaving the name behind
  printf '%s\n' "$FM" | grep -qx "name: $a" \
    || { fail "cast agents" "$F does not name itself $a"; S=1; }
  # break: copying the agent into .claude/agents, where an edit to the source in
  # plugins/cast is not live in the session
  [ -L ".claude/agents/$a.md" ] \
    || { fail "cast agents" ".claude/agents/$a.md is not a symbolic link"; S=1; }
  [ "$(readlink -f ".claude/agents/$a.md")" = "$PWD/plugins/cast/agents/$a.md" ] \
    || { fail "cast agents" ".claude/agents/$a.md does not point at plugins/cast/agents/$a.md"; S=1; }
  # break: handing the agent Edit, so it can change the source it was dispatched
  # to read about - neither of the two edits a file
  printf '%s\n' "$FM" | grep -q '^tools:.*Edit' \
    && { fail "cast agents" "$F may edit source files"; S=1; }
  # break: returning the report itself, which pays the dispatch and lands the
  # whole graph in the caller's context anyway
  grep -q '^## Return$' "$F" \
    || { fail "cast agents" "$F states no return contract"; S=1; }
  grep -qi 'never paste the page markup' "$F" \
    || { fail "cast agents" "$F does not keep the page markup out of its return"; S=1; }
  # break: leaving Artifact out, which sends the page back as a path and makes
  # the caller publish a file it did not write - the one handling the boundary
  # exists to keep out of its context
  printf '%s\n' "$FM" | grep -q '^tools:.*Artifact' \
    || { fail "cast agents" "$F cannot publish the page it renders"; S=1; }
  grep -qF 'page: <url>' "$F" \
    || { fail "cast agents" "$F does not return the link it published"; S=1; }
done
# break: dropping the skill the agent's procedure lives in, so it rediscovers the
# cast flags on every run - the duplication the boundary exists to avoid
agent_declares() {
  F="plugins/cast/agents/$1.md"
  [ -f "$F" ] || return 0
  sed -n '2,/^---$/p' "$F" | grep -qx "  - $2" \
    || { fail "cast agents" "$F does not declare the $2 skill"; S=1; }
}
agent_declares graph-analyst cast:map
agent_declares graph-analyst map
agent_declares refactor-planner cast:plan
agent_declares refactor-planner plan
# break: letting the planner edit ahead of an accepted simulation, which is the
# one thing the draft-simulate-judge loop exists to prevent
grep -qi 'no source file' plugins/cast/agents/refactor-planner.md \
  || { fail "cast agents" "the planner does not forbid itself a source edit"; S=1; }
# break: rendering the page without --fragment, which the caller then cannot
# publish as an Artifact
grep -qF -- '--fragment' plugins/cast/agents/graph-analyst.md \
  || { fail "cast agents" "the analyst does not render a publishable fragment"; S=1; }
# break: adding the agents and routing nothing to them, so the session keeps
# reading the graph in its own context
for a in graph-analyst refactor-planner; do
  grep -q "$a" plugins/cast/rules/cast.md \
    || { fail "cast agents" "the cast rule never names $a"; S=1; }
done
# Everything an agent writes is throwaway and belongs outside the checkout - the
# caller publishes the page and never wants it back.
for a in graph-analyst refactor-planner; do
  F="plugins/cast/agents/$a.md"
  [ -f "$F" ] || continue
  # break: rendering into the tree - `.cast/render/<slug>.html` was the first
  # version of both agents, and left a page behind on every run
  grep -qF -- '--html "$SCRATCH/' "$F" \
    || { fail "cast agents" "$F does not render into the scratch directory"; S=1; }
  grep -qF -- '--html <root>/' "$F" \
    && { fail "cast agents" "$F still renders into the checkout"; S=1; }
  # break: naming a scratch directory and never saying where it comes from, so
  # an agent whose task names none writes $SCRATCH/... into its working directory
  grep -qF 'mktemp -d' "$F" \
    || { fail "cast agents" "$F has no scratch directory where its task names none"; S=1; }
  # break: returning a relative path, which the caller cannot resolve - it does
  # not share the agent's working directory
  grep -qi 'absolute path' "$F" \
    || { fail "cast agents" "$F does not return absolute paths"; S=1; }
done
# The directory the task names has to reach the skill line, and nothing expands
# $ARGUMENTS for an agent that runs it itself.
# break: the agent that runs the line bare - a task about `src` answered with a
# map of the whole project, which is what the caller reads as the answer
for a in graph-analyst refactor-planner; do
  F="plugins/cast/agents/$a.md"
  [ -f "$F" ] || continue
  grep -qF 'ARGUMENTS=' "$F" \
    || { fail "cast agents" "$F never sets ARGUMENTS, so a directory in its task cannot reach the line"; S=1; }
  grep -qi 'your task names it' "$F" \
    || { fail "cast agents" "$F does not take the directory from its task"; S=1; }
  grep -qi 'whole project' "$F" \
    || { fail "cast agents" "$F does not say what it reads where its task names no directory"; S=1; }
done
# break: the rule dispatching to an agent and never telling it which directory,
# which is the same failure one level up
grep -qi 'name the directory in the task' plugins/cast/rules/cast.md \
  || { fail "cast agents" "the cast rule does not hand the agent the directory the question is about"; S=1; }
# The plan goes to scratch with everything else - `cast plan simulate` takes a
# path. break: sending it back to `.cast/plans/` by default, which leaves a draft
# in the tree on every run, accepted or not.
grep -qF '$SCRATCH/<name>.json' plugins/cast/agents/refactor-planner.md \
  || { fail "cast agents" "the planner does not draft into the scratch directory"; S=1; }
# break: dropping the one case that does belong in the checkout, so a plan the
# caller asked to keep is written where nothing looks for it
grep -qF '<root>/.cast/plans/<name>.json' plugins/cast/agents/refactor-planner.md \
  || { fail "cast agents" "the planner never keeps a plan beside the code"; S=1; }
# AC5 the planner can be handed a plan that already exists. break: taking the
# plan out of the task and never putting it on the skill's line, where nothing
# expands $ARGUMENTS for the agent - the plan is then silently redrafted.
grep -qi 'your task may name a plan' plugins/cast/agents/refactor-planner.md \
  || { fail "cast agents" "the planner does not take a plan from its task"; S=1; }
grep -qF 'ARGUMENTS="<goal> <plan> <dir>"' plugins/cast/agents/refactor-planner.md \
  || { fail "cast agents" "the planner never passes the plan to the skill line with the goal and the root"; S=1; }
# break: returning a fresh scratch draft where a named plan was continued, so the
# caller cannot tell which file now holds the plan
grep -qF 'it is that file you return' plugins/cast/agents/refactor-planner.md \
  || { fail "cast agents" "the planner does not return the file it continued"; S=1; }
[ "$S" = 0 ] && ok "cast agents"


# --- cast plan skill --------------------------------------------------------
# AC4/AC5 the plan skill drafts the plan itself and loops on the simulation, and
# it says what a simulation has to say before anyone is allowed to edit a file.
S=0
F="plugins/cast/skills/plan/SKILL.md"
if [ ! -f "$F" ]; then fail "cast plan skill" "$F is missing"; S=1; else
  # break: leaving allowed-tools at Bash, Read, so the skill cannot write the
  # plan file it is told to draft
  sed -n '2,/^---$/p' "$F" | grep -q '^allowed-tools:.*Write' \
    || { fail "cast plan skill" "the plan skill cannot write the plan it drafts"; S=1; }
  # break: requiring a plan file someone else wrote - the old behaviour, which
  # stopped and asked instead of drafting
  grep -qiE 'ask (which|for a) plan|never simulate a plan you wrote' "$F" \
    && { fail "cast plan skill" "the plan skill still asks for a plan instead of drafting one"; S=1; }
  grep -qF 'The plan is yours to write' "$F" \
    || { fail "cast plan skill" "the plan skill does not claim the drafting as its own"; S=1; }
  # break: naming the plan file without saying the skill writes it
  grep -qF '<root>/.cast/plans/<name>.json' "$F" \
    || { fail "cast plan skill" "the plan skill does not name the file it drafts"; S=1; }
  # break: dropping an operation from the shape, so a draft is guesswork
  for o in move merge invert split; do
    grep -qF "\"op\":\"$o\"" "$F" \
      || { fail "cast plan skill" "the plan skill does not give the shape of a $o operation"; S=1; }
  done
  # break: describing one pass instead of a loop, so a rejected plan is reported
  # rather than redrafted
  for h in 'Draft' 'Simulate' 'Judge' 'Redraft'; do
    grep -qE "^[0-9]+\. \*\*$h\.\*\*" "$F" \
      || { fail "cast plan skill" "the plan skill has no $h step"; S=1; }
  done
  grep -qF 'until a simulation is accepted' "$F" \
    || { fail "cast plan skill" "the plan skill does not loop until a simulation is accepted"; S=1; }
  # break: the loop that never runs the simulator
  grep -qF 'cast plan simulate <name> --root <root>' "$F" \
    || { fail "cast plan skill" "the plan skill never runs the simulation on the root it resolved"; S=1; }
  # AC5 break: dropping either half of the judgement, which leaves accepted to taste
  grep -q '^## What accepts a simulation$' "$F" \
    || { fail "cast plan skill" "the plan skill does not say what accepts a simulation"; S=1; }
  grep -q '^## What rejects it$' "$F" \
    || { fail "cast plan skill" "the plan skill does not say what rejects a simulation"; S=1; }
  # break: accepting a plan that adds a cycle or a violation
  grep -qF 'any cycle, any violation' "$F" \
    || { fail "cast plan skill" "a plan that adds a cycle or a violation is not rejected"; S=1; }
  # break: letting the edits start before the simulation is accepted, which is
  # the whole point of planning first
  grep -q '^## Edit nothing until it is accepted$' "$F" \
    || { fail "cast plan skill" "the plan skill does not forbid editing before a simulation is accepted"; S=1; }
  grep -qF 'No source file is touched while this loop runs' "$F" \
    || { fail "cast plan skill" "the plan skill does not forbid touching a source file during the loop"; S=1; }
  # AC4 break: taking a plan on the argument and never saying how it is carried
  # on, which leaves a continued plan drafted from scratch under its own name
  grep -q '^## Continuing a plan you were handed$' "$F" \
    || { fail "cast plan skill" "the plan skill does not say how a plan it was handed is continued"; S=1; }
  # break: copying the plan to a new name instead of editing the one named
  grep -qF 'The named file is the one you edit' "$F" \
    || { fail "cast plan skill" "the plan skill does not edit the plan file it was handed"; S=1; }
  # break: appending an operation against the scanned graph, which names a module
  # an earlier operation renamed away and dies as an unknown module
  grep -qF 'the ids to spell are the ones the printed operations leave' "$F" \
    || { fail "cast plan skill" "an appended operation is not told which module ids the plan leaves"; S=1; }
  # break: simulating and judging the addition alone, so the operations the plan
  # arrived with are never weighed again
  grep -qF 'never the addition alone' "$F" \
    || { fail "cast plan skill" "the continued plan is not judged whole"; S=1; }
fi
[ "$S" = 0 ] && ok "cast plan skill"


# --- cast render skill ------------------------------------------------------
# AC7 a skill reaches the renderer: the plan's mermaid is what a refactoring
# issue carries, and the page is the manual look - at the plan and at today.
S=0
P="plugins/cast/skills/plan/SKILL.md"
M="plugins/cast/skills/map/SKILL.md"
if [ ! -f "$P" ] || [ ! -f "$M" ]; then fail "cast render skill" "a cast skill is missing"; S=1; else
  # break: leaving --plan to the command line, so the picture in the issue is
  # the graph as it is today and not the one the plan would leave
  grep -qF 'cast render --mermaid --plan <name> --root <root>' "$P" \
    || { fail "cast render skill" "no skill draws the plan as mermaid"; S=1; }
  grep -A2 'cast render --mermaid --plan' "$P" | grep -qi 'issue' \
    || { fail "cast render skill" "the plan mermaid is not named as the picture an issue carries"; S=1; }
  # break: dropping the page, leaving a mermaid block as the only way to look
  grep -qF 'cast render --html <file> --fragment --plan <name> --root <root>' "$P" \
    || { fail "cast render skill" "no skill opens the plan as a page"; S=1; }
  # break: a page of the plan and no page of the current state to compare it to
  grep -qF 'cast render --html <file> --fragment --root <root>' "$M" \
    || { fail "cast render skill" "no skill opens the current state as a page"; S=1; }
  # break: rendering a plan and letting it be mistaken for a scan that wrote
  grep -qF 'exits 2 having drawn nothing' "$P" \
    || { fail "cast render skill" "the plan skill does not say an unapplicable plan draws nothing"; S=1; }
fi
[ "$S" = 0 ] && ok "cast render skill"

# --- the cast rule lives in the plugin --------------------------------------
# A project that installs cast gets the rule with it; this repository reads the
# same file through a link, so the two can never drift.
S=0
[ -f plugins/cast/rules/cast.md ] || { fail "cast rule" "plugins/cast/rules/cast.md is gone"; S=1; }
# break: copying the rule back into .claude/rules instead of linking it
[ "$(readlink .claude/rules/cast.md 2>/dev/null)" = "../../plugins/cast/rules/cast.md" ] \
  || { fail "cast rule" ".claude/rules/cast.md is not a link to the plugin's rule"; S=1; }
# break: dropping the split that sends the page to the user and the mermaid to an issue
grep -qF 'cast render --html' plugins/cast/rules/cast.md \
  || { fail "cast rule" "the rule no longer names the page as what the user is sent"; S=1; }
grep -qF 'cast render --mermaid' plugins/cast/rules/cast.md \
  || { fail "cast rule" "the rule no longer names mermaid as what an issue carries"; S=1; }
[ "$S" = 0 ] && ok "cast rule"

# --- cast reads this repository ---------------------------------------------
# #58: an import written as an expression is one cast counts and never resolves,
# so a project whose own imports are all expressions has a graph with no edge in
# it - and nothing built on edges says anything about it.
S=0
# break: writing an internal require as `require(path.join(__dirname,'lib.js'))`
# again, which takes the file back out of the graph
CAST_SELF_BAD="$(grep -rln "require(require('path')\.join(__dirname\|require(path\.join(__dirname" plugins/forge/scripts plugins/cast/scripts 2>/dev/null)"
[ -z "$CAST_SELF_BAD" ] \
  || { fail "cast reads itself" "an internal require is written as an expression in: $CAST_SELF_BAD"; S=1; }
"$CAST_BIN" scan --root . >/dev/null 2>&1 \
  || { fail "cast reads itself" "cast scan did not run on this repository"; S=1; }
CAST_SELF="$("$CAST_BIN" report --root . 2>&1)"
CAST_SELF_N="$(printf '%s\n' "$CAST_SELF" | sed -n 's/^  module \([0-9]*\),.*$/\1/p' | head -1)"
[ -n "$CAST_SELF_N" ] \
  || { fail "cast reads itself" "the report names no module edge count: $CAST_SELF"; S=1; }
# every forge script that reads lib.js is one edge, and they are what the graph
# was missing entirely
[ "${CAST_SELF_N:-0}" -ge 6 ] \
  || { fail "cast reads itself" "cast finds $CAST_SELF_N module edges in its own repository"; S=1; }
# the imports that cannot be literal stay opaque, and stay counted
# break: teaching the adapter to guess at an expression, which invents an edge
printf '%s\n' "$CAST_SELF" | grep -q '^opaque [1-9]' \
  || { fail "cast reads itself" "no import is opaque any more, so an expression was guessed at: $CAST_SELF"; S=1; }
# the drawing has something to draw: one layer holds every module here, so the
# arrows are at module altitude
# break: the same expressions, which leave the graph a single box
"$CAST_BIN" render --mermaid --expand plugins --root . 2>&1 | grep -q ' -->|' \
  || { fail "cast reads itself" "the drawing of this repository carries no arrow"; S=1; }
[ "$S" = 0 ] && ok "cast reads itself"

# --- a skill's preamble never decides whether the skill loads ---------------
# #59: the shell block at the top of a cast skill is read for its exit code, and
# a non-zero one costs the caller the skill itself - the body never loads. None
# of the states below is a failure, so none of them may exit non-zero.
S=0
PRE="$(mktemp -d)"
mkdir -p "$PRE/empty"
preamble_of() { sed -n 's/^!`\(.*\)`$/\1/p' "plugins/cast/skills/$1/SKILL.md"; }
run_pre() {
  ( cd "$2" && CLAUDE_PLUGIN_ROOT="$PWD_ROOT/plugins/cast" ARGUMENTS="$3" bash -c "$4" 2>&1 )
}
PWD_ROOT="$PWD"
for k in map plan; do
  L="$(preamble_of "$k")"
  [ -n "$L" ] || { fail "cast skill preamble" "the $k skill carries no preamble to run"; S=1; continue; }
  # break: `ls .cast/plans` with nothing to list, or `scan && report` passing a
  # scan's exit 2 on - either one loses the skill on its first run in a project
  OUT="$(run_pre "$k" "$PRE/empty" "" "$L")"; RC=$?
  [ "$RC" = 0 ] \
    || { fail "cast skill preamble" "the $k preamble exited $RC in a project with nothing to look at: $OUT"; S=1; }
  printf '%s\n' "$OUT" | grep -q '^cast root: ' \
    || { fail "cast skill preamble" "the $k preamble does not name the root it read: $OUT"; S=1; }
done
# where there is something to list, it is still listed
# break: silencing the listing along with its exit code
mkdir -p "$PRE/withplan/.cast/plans" && printf '{"operations":[]}\n' > "$PRE/withplan/.cast/plans/cut.json"
OUT="$(run_pre plan "$PRE/withplan" "" "$(preamble_of plan)")"
printf '%s\n' "$OUT" | grep -qF 'cut.json' \
  || { fail "cast skill preamble" "the plan preamble no longer lists the plans it found: $OUT"; S=1; }
printf '%s\n' "$OUT" | grep -qF 'no plan written yet' \
  && { fail "cast skill preamble" "the plan preamble says there is no plan while listing one: $OUT"; S=1; }
rm -rf "$PRE"
[ "$S" = 0 ] && ok "cast skill preamble"

# --- cast plan continue -----------------------------------------------------
# #68 AC1-AC3: the plan skill takes a plan that is already written down beside
# the goal and the directory. The preamble is run, not read - what the model gets
# is its output, so every case here executes the line the skill carries.
S=0
PLAN_REPO="$PWD"
plan_line() {
  ARGS="$1" DIR="$2" PLAN_REPO="$PLAN_REPO" bash -c '
    cd "$DIR" || exit 1
    export CLAUDE_PLUGIN_ROOT="$PLAN_REPO/plugins/cast"
    ARGUMENTS="$ARGS"
    '"$(sed -n 's/^!`\(.*\)`$/\1/p' plugins/cast/skills/plan/SKILL.md)"'
  ' 2>&1
}
# AC1 a bare name is read under <root>/.cast/plans/<name>.json, and the preamble
# says which plan it read.
# break: dropping the resolution, so a plan handed to the skill is redrafted
CAST_PC="$(plan_line 'break the cycle cut' "$CASTFIX")"; RC=$?
[ "$RC" = 0 ] \
  || { fail "cast plan continue" "the plan preamble exited $RC on a plan it was handed: $CAST_PC"; S=1; }
printf '%s\n' "$CAST_PC" | grep -qx 'cast plan: cut' \
  || { fail "cast plan continue" "the preamble did not report the plan it read: $CAST_PC"; S=1; }
# AC2 where a plan is named, its operations and its simulation come before any
# drafting - against the graph the same line just scanned.
# break: naming the plan and printing nothing about it, which leaves the loop
# starting from scratch anyway
printf '%s\n' "$CAST_PC" | grep -qF 'move src/rel.ts -> pkg/rel.ts' \
  || { fail "cast plan continue" "the preamble did not show the operations of the plan it read: $CAST_PC"; S=1; }
printf '%s\n' "$CAST_PC" | grep -q '^module edges 8 -> 7' \
  || { fail "cast plan continue" "the preamble did not simulate the plan it read: $CAST_PC"; S=1; }
printf '%s\n' "$CAST_PC" | grep -q '^modules ' \
  || { fail "cast plan continue" "the preamble stopped reporting the graph it drafts against: $CAST_PC"; S=1; }
# AC1 a path to a plan file anywhere is read too - that is where the agents keep
# theirs. break: resolving every word under <root>/.cast/plans
PLANC="$(mktemp -d)"; cp "$CASTFIX/.cast/plans/cut.json" "$PLANC/keep.json"
CAST_PCP="$(plan_line "break the cycle $PLANC/keep.json" "$CASTFIX")"; RC=$?
[ "$RC" = 0 ] \
  || { fail "cast plan continue" "the plan preamble exited $RC on a plan given by path: $CAST_PCP"; S=1; }
printf '%s\n' "$CAST_PCP" | grep -qxF "cast plan: $PLANC/keep.json" \
  || { fail "cast plan continue" "the preamble did not report the plan path it read: $CAST_PCP"; S=1; }
printf '%s\n' "$CAST_PCP" | grep -q '^module edges 8 -> 7' \
  || { fail "cast plan continue" "a plan given by path was not simulated: $CAST_PCP"; S=1; }
rm -rf "$PLANC"
# the plan and the directory arrive together, and the trailing word is still the
# root. break: reading the plan off the end of the argument, where the root is
CAST_PCD="$(plan_line 'break the cycle cut .' "$CASTFIX")"
printf '%s\n' "$CAST_PCD" | grep -qx 'cast root: .' \
  || { fail "cast plan continue" "a plan before the directory cost the root: $CAST_PCD"; S=1; }
printf '%s\n' "$CAST_PCD" | grep -qx 'cast plan: cut' \
  || { fail "cast plan continue" "a plan before the directory was not read: $CAST_PCD"; S=1; }
# AC2/AC3 a goal that names no plan lists what the project holds and drafts from
# scratch, and AC3 costs nothing: the word is never handed to `cast plan
# simulate`, whose exit 2 would cost the skill its body.
# break: passing the trailing word of the goal to the simulator
CAST_PN2="$(plan_line 'break the cycle between ui and data' "$CASTFIX")"; RC=$?
[ "$RC" = 0 ] \
  || { fail "cast plan continue" "a goal naming no plan exited $RC: $CAST_PN2"; S=1; }
printf '%s\n' "$CAST_PN2" | grep -qx 'cast plan: none' \
  || { fail "cast plan continue" "a word that names no plan was not reported as none: $CAST_PN2"; S=1; }
printf '%s\n' "$CAST_PN2" | grep -qF 'no plan at ' \
  && { fail "cast plan continue" "a word that names no plan was handed to the simulator: $CAST_PN2"; S=1; }
printf '%s\n' "$CAST_PN2" | grep -qF 'cut.json' \
  || { fail "cast plan continue" "the preamble no longer lists the plans it found: $CAST_PN2"; S=1; }
# AC3 a goal that names an existing file that is not a plan - `move tool.sh
# somewhere else`, with tool.sh in the root - still drafts from scratch: only a
# `*.json` holding operations is a plan, so nothing else is labelled one or cat'd
# into the preamble.
# break: resolving any word the `-f` test accepts as the plan
printf 'echo hi\n' > "$CASTFIX/tool.sh"
printf '{"name":"x"}\n' > "$CASTFIX/pkg.json"
CAST_PF="$(plan_line 'move tool.sh somewhere else' "$CASTFIX")"; RC=$?
[ "$RC" = 0 ] \
  || { fail "cast plan continue" "a goal naming a plain file exited $RC: $CAST_PF"; S=1; }
printf '%s\n' "$CAST_PF" | grep -qx 'cast plan: none' \
  || { fail "cast plan continue" "a file that is no plan was labelled the plan: $CAST_PF"; S=1; }
printf '%s\n' "$CAST_PF" | grep -qF 'echo hi' \
  && { fail "cast plan continue" "a file that is no plan was printed as the plan: $CAST_PF"; S=1; }
# a json file that carries no operations is no plan either
# break: taking any `*.json` path as a plan without reading it
CAST_PJ="$(plan_line 'move pkg.json somewhere else' "$CASTFIX")"
printf '%s\n' "$CAST_PJ" | grep -qx 'cast plan: none' \
  || { fail "cast plan continue" "a json holding no operations was labelled the plan: $CAST_PJ"; S=1; }
rm -f "$CASTFIX/tool.sh" "$CASTFIX/pkg.json"
# AC3 a project that holds no plan at all is the same: exit 0, and none.
# break: `cat` or `ls` on a directory that is not there deciding the exit code
PLANE="$(mktemp -d)"
CAST_PE="$(plan_line 'break the cycle cut' "$PLANE")"; RC=$?
[ "$RC" = 0 ] \
  || { fail "cast plan continue" "the plan preamble exited $RC in a project holding no plan: $CAST_PE"; S=1; }
printf '%s\n' "$CAST_PE" | grep -qx 'cast plan: none' \
  || { fail "cast plan continue" "a project holding no plan did not report none: $CAST_PE"; S=1; }
rm -rf "$PLANE"
# the body says what the two lines mean, or the model reads an unexplained one
# break: teaching the line and leaving the skill body behind
for t in 'cast plan: <name>' 'cast plan: none'; do
  grep -qF "$t" plugins/cast/skills/plan/SKILL.md \
    || { fail "cast plan continue" "the plan skill never says what $t means"; S=1; }
done
[ "$S" = 0 ] && ok "cast plan continue"

# --- the cast rule reaches a project that installs cast ---------------------
# The rule is injected at SessionStart, never copied into the project: a copy
# ages the moment the plugin is updated and nothing notices.
S=0
grep -q 'scripts/session-start.js' plugins/cast/hooks/hooks.json \
  || { fail "cast rule delivery" "the cast hooks no longer run the session start script"; S=1; }
grep -q "'rules', 'cast.md'" plugins/cast/scripts/session-start.js \
  || { fail "cast rule delivery" "the session start hook no longer reads the rule"; S=1; }
CH="$(mktemp -d)"
start_cast() { echo '{}' | env CLAUDE_PROJECT_DIR="$1" node plugins/cast/scripts/session-start.js; }
# break: dropping the injection, leaving the rule inert wherever cast is installed
start_cast "$CH" | grep -q 'cast render --mermaid' \
  || { fail "cast rule delivery" "an installed plugin did not inject its rule"; S=1; }
# a project that carries the rule itself already loads it as a project rule
# break: injecting always, so the cast checkout pays for its own rule twice
mkdir -p "$CH/.claude/rules" && : > "$CH/.claude/rules/cast.md"
start_cast "$CH" | grep -q 'cast render --mermaid' \
  && { fail "cast rule delivery" "a project that carries the rule was charged for it twice"; S=1; }
rm -rf "$CH"
[ "$S" = 0 ] && ok "cast rule delivery"

exit "$FAILED"
