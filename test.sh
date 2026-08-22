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
trap 'rm -rf "$FIX" "$PASSFIX" "$CTX" "$CASTFIX"' EXIT
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
printf 'use "two"\n' > "$CASTFIX/pkg/one.toy"
printf 'nothing here\n' > "$CASTFIX/pkg/two.toy"
# The layers the fixture is read at: one module in its own layer, the rest of src
# below it, and pkg claimed by no glob at all.
cat > "$CASTFIX/.cast/layers.json" <<'JSON'
{ "src/a.ts": "ui", "src/**": "logic" }
JSON

CAST_BIN="$PWD/plugins/cast/bin/cast"
S=0
(cd "$CASTFIX" && "$CAST_BIN" scan >/dev/null 2>&1) \
  || { fail "cast graph" "cast scan did not run"; S=1; }
CAST_REPORT="$(cd "$CASTFIX" && "$CAST_BIN" report 2>&1)"
# Assert against the written graph, never against an in-process call: the file is
# the contract, and a scan that computes the right answer without writing it is a
# scan nothing downstream can read.
graph() { CASTFIX="$CASTFIX" node -e '
  const bad=(s)=>{console.log(s);process.exit(1)}
  let g
  try { g=JSON.parse(require("fs").readFileSync(process.env.CASTFIX+"/.cast/graph.json","utf8")) }
  catch(e) { bad("no readable .cast/graph.json: "+e.message) }
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
  if (!e) bad("a project adapter pattern produced no edge")
  if (e.to!=="pkg/two.toy") bad("a project adapter resolver was not used: "+e.to)
')" || { fail "cast graph" "$O"; S=1; }
[ "$S" = 0 ] && ok "cast graph"

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
printf '%s\n' "$CAST_EDGES" | grep -q '^edges ui -> logic 3$' \
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
printf '%s\n' "$CAST_EXP" | grep -q '^  L_ui -->|1| M_src_b_ts$' \
  || { fail "cast expand" "an edge into the expanded layer did not reach a module: $CAST_EXP"; S=1; }
[ "$S" = 0 ] && ok "cast expand"

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
[ "$S" = 0 ] && ok "cast html"


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

# AC10 cast rules preview <rule> reports how many module edges that rule would
# flag today, counted per edge and not per module
S=0
# The rule under preview is written nowhere: rules.json holds an unrelated one,
# so a preview that only looks up a written rule finds nothing to report.
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [ { "name": "ui-off-pkg", "severity": "error", "from": "ui", "to": "unassigned",
                   "kinds": ["value", "type", "dynamic"] } ] }
JSON
TRY='{ "name": "try-me", "severity": "error", "from": "ui", "to": "logic",
       "kinds": ["value", "type", "dynamic"] }'
CAST_PRE="$(cd "$CASTFIX" && "$CAST_BIN" rules preview "$TRY" 2>&1)"; RC=$?
# src/a.ts is the only module in `ui` and carries three edges into `logic`
# break: counting the modules that violate the rule, or the distinct layer
# edges, either of which answers 1 where three imports have to move
printf '%s\n' "$CAST_PRE" | grep -q '^3 edges flagged in 1 module of ' \
  || { fail "cast preview" "the edges a rule would flag were not counted per edge: $CAST_PRE"; S=1; }
# break: previewing only a rule already in rules.json, which cannot try one
printf '%s\n' "$CAST_PRE" | grep -q '^try-me (error) ui -> logic 3$' \
  || { fail "cast preview" "a rule that is written nowhere was not previewed: $CAST_PRE"; S=1; }
# break: dropping the sites, which leaves a count nobody can act on
printf '%s\n' "$CAST_PRE" | grep -q '^    src/a.ts:6 -> src/c.ts (dynamic)$' \
  || { fail "cast preview" "the flagged edges were not named with their sites: $CAST_PRE"; S=1; }
# break: routing the preview through the check's exit code, which fails a build
# on a rule the project has not agreed to
[ "$RC" = 0 ] || { fail "cast preview" "a preview of a violated error rule exited $RC, not 0: $CAST_PRE"; S=1; }
# today, not in the abstract: the exceptions the project has already written
# down are the ones a new rule lands beside
cat > "$CAST_RULES" <<'JSON'
{ "forbidden": [],
  "allowed": [ { "name": "a-may-type-t", "severity": "error", "from": "src/a.ts", "to": "src/t.ts",
                 "kinds": ["type"] } ] }
JSON
CAST_PRE2="$(cd "$CASTFIX" && "$CAST_BIN" rules preview "$TRY" 2>&1)"
# break: previewing the rule alone, which counts an edge an allowed rule drops
printf '%s\n' "$CAST_PRE2" | grep -q '^2 edges flagged in 1 module of ' \
  || { fail "cast preview" "an edge the allowed list claims was still flagged: $CAST_PRE2"; S=1; }
# break: dropping the unknown-key report on the preview path, which reads as a
# rule the preview evaluated whole
CAST_PRE3="$(cd "$CASTFIX" && "$CAST_BIN" rules preview \
  '{ "name": "guess", "from": "ui", "to": "logic", "unless": "friday" }' 2>&1)"
printf '%s\n' "$CAST_PRE3" | grep -q 'not evaluated: guess: unless' \
  || { fail "cast preview" "a previewed attribute the evaluator cannot decide was passed silently: $CAST_PRE3"; S=1; }
# break: reading a malformed rule as a rule that flags nothing
CAST_PRE4="$(cd "$CASTFIX" && "$CAST_BIN" rules preview 'not json' 2>&1)"; RC=$?
[ "$RC" = 2 ] || { fail "cast preview" "an unreadable rule exited $RC, not 2: $CAST_PRE4"; S=1; }
[ "$S" = 0 ] && ok "cast preview"


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

exit "$FAILED"
