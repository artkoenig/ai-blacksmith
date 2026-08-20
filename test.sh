#!/usr/bin/env bash
# Every check that runs without a Claude Code session.
# Prints one line per suite. A failure prints "FAIL <suite>: <what>".
set -uo pipefail
cd "$(dirname "$0")"

FAILED=0
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAILED=1; }
ok()   { printf 'ok   %s\n' "$1"; }

# --- manifest and syntax ----------------------------------------------------
# The plugin pins no version on purpose - it is released from the tip of main, so
# the commit is the version. --strict warns about exactly that one thing, and
# every other line it prints is a break.
if command -v claude >/dev/null; then
  V="$(claude plugin validate ./plugins/forge --strict 2>&1 \
        | grep '^  > ' | grep -v '^  > version: No version specified')"
  [ -z "$V" ] || fail manifest "claude plugin validate rejected plugins/forge:${V}"
fi
for f in plugins/forge/workflows/*.js plugins/forge/scripts/*.js; do
  node --check "$f" 2>/dev/null || fail syntax "$f"
done
for f in plugins/forge/bin/*; do
  bash -n "$f" 2>/dev/null || fail syntax "$f"
  [ -x "$f" ] || fail permissions "$f is not executable"
done
for f in plugins/forge/scripts/*.js; do [ -x "$f" ] || fail permissions "$f is not executable"; done
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
# A cloud session whose plugin checkout is behind the marketplace tip is told so.
# The version is the SHA path segment of CLAUDE_PLUGIN_ROOT, the tip comes from
# the marketplace clone's own origin.
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
start() { # <sha> <marketplace dir> [remote flag]
  echo '{}' | env CLAUDE_CONFIG_DIR="$SS/cfg" \
    CLAUDE_PLUGIN_ROOT="$SS/cfg/plugins/repos/$2/$1/plugins/forge" \
    CLAUDE_CODE_REMOTE="${3-true}" node plugins/forge/scripts/session-start.js
}
# an outdated checkout is named - break: dropping the mismatch branch
start 0000000 mkt | grep -q "outdated forge plugin" \
  || { fail staleness "no warning for a checkout behind the tip"; S=1; }
# it names the update command with the marketplace it came from - break: a hard-coded name
start 0000000 mkt | grep -q "forge@mkt" \
  || { fail staleness "the warning did not name the marketplace to update from"; S=1; }
# the current checkout is not warned - break: warning without comparing
start "${TIP:0:7}" mkt | grep -q "outdated forge plugin" \
  && { fail staleness "a session on the tip was warned"; S=1; }
# a local session makes no network call and no noise - break: dropping the remote gate
start 0000000 mkt '' | grep -q "outdated forge plugin" \
  && { fail staleness "a local session was warned"; S=1; }
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

# --- the run starts on demand -----------------------------------------------
# Writing an issue spends no dispatch. The behaviour lives in prose, so the
# prose is what is checked: a skill that ends by invoking the workflow starts
# work nobody asked for.
S=0
# break: restoring a "## 4. Start the run" step that invokes /forge:work
grep -q '^## 4. Hand it over$' plugins/forge/skills/issue/SKILL.md \
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
# English. Both halves are prose, so the prose is what is checked. The style
# carries the session's half, the agent protocol the agents' half - neither
# restates the other.
S=0
# break: dropping the reply-language line and going English-only again
grep -q "the language the user writes in" plugins/forge/output-styles/terse.md \
  || { fail language "the output style no longer replies in the user's language"; S=1; }
# break: dropping the English-artifacts rule from either reader
grep -q '^- Write English into every file' plugins/forge/output-styles/terse.md \
  || { fail language "the output style no longer requires English in files"; S=1; }
grep -q '^Write English into every file' plugins/forge/skills/agent-protocol/SKILL.md \
  || { fail language "the agent protocol no longer requires English in files"; S=1; }
[ "$S" = 0 ] && ok "output language"

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
  const live={review:0,peak:0}
  const agent=async(prompt,o)=>{
    calls.push(o.label)
    if(o.label.startsWith('review')){
      live.review++;live.peak=Math.max(live.peak,live.review)
      await new Promise(r=>setTimeout(r,1))
      live.review--
    }
    const inc=(o.label.split(':')[1]||'').split('/')[1]||'1'
    if(/^(implement|repair)/.test(o.label)) return {status:'implemented',branch:'b',worktree:a.increments?'/wt':'',base:'b0',sha:'c',summary:'s'}
    const q=verdicts[inc]||[]
    return q.shift()??{pass:true,failed:[],merged:!conflicts.includes(inc)}
  }
  const said=[]
  return new Function('agent','phase','log','parallel','args',`return (async () => {${src}})()`)
    (agent,()=>{},m=>said.push(m),t=>Promise.all(t.map(f=>f())),a).then(r=>({r,calls,peak:live.peak,said}))
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
  ;({said}=await run('1',{verdicts:{1:[{pass:false,failed:['AC1'],notes:['AC1: still red']}]}}))
  eq(said,['1: s','1: rejected - AC1 - AC1: still red','1: repair 1 - s','1: passed, landed'],
    'a rejection and its repair did not reach the user')

  eq((await run('')).r.status,'error','a missing issue id was accepted')
  eq((await run({issue:'1',agentPrefix:''})).r.status,'done','agentPrefix did not resolve')
})()
JS
[ "$FAILED" = 0 ] && ok "workflow control flow"

# --- journal status ---------------------------------------------------------
# A workflow journal carries every agent's whole return value. Reading it to
# learn whether the run is finished costs all of them, so the status is one
# call: started = running, result = done, aborted = dead.
JRN="$(mktemp -d)"
trap 'rm -rf "$FIX" "$PASSFIX" "$CTX" "$JRN"' EXIT
WF="$JRN/cfg/projects/p/s/subagents/workflows"
mkdir -p "$WF/wf_a" "$WF/wf_b"
# The last line is half written on purpose: the file is appended while the run
# goes on, and a torn line is the run still going, not a broken journal.
cat > "$WF/wf_a/journal.jsonl" <<'JSONL'
{"type":"started","key":"v2:aaa","agentId":"a1a1a1a1a1"}
{"type":"result","key":"v2:aaa","agentId":"a1a1a1a1a1","result":{"status":"implemented","summary":"padding padding padding padding padding padding padding padding padding TAILMARK"}}
{"type":"started","key":"v2:bbb","agentId":"b2b2b2b2b2"}
{"type":"started","key":"v2:ccc","agentId":"c3c3c3c3c3"}
{"type":"aborted","key":"v2:ccc","agentId":"c3c3c3c3c3"}
{"type":"started","key":"v2:dd
JSONL
printf '{"type":"started","key":"v2:zzz","agentId":"z9z9z9z9z9"}\n' > "$WF/wf_b/journal.jsonl"
touch -m -t 200001010000 "$WF/wf_a/journal.jsonl"

S=0
JOUT="$("$BIN/forge-journal" "$WF/wf_a")"; RC=$?
# the question is answered before anything else - break: dropping the tally line
[ "$(printf '%s\n' "$JOUT" | head -1)" = "1 running, 1 done, 1 dead" ] \
  || { fail journal "the status did not open with the tally"; S=1; }
# it always answers - break: exiting non-zero on a journal it could read
[ "$RC" = 0 ] || { fail journal "reading a journal did not exit 0"; S=1; }
# result = done - break: mapping a returned agent to anything else
printf '%s\n' "$JOUT" | grep -q "^done     a1a1a1a1" \
  || { fail journal "an agent that returned was not reported done"; S=1; }
# started without a result = running - break: reporting an unfinished agent as done
printf '%s\n' "$JOUT" | grep -q "^running  b2b2b2b2" \
  || { fail journal "an agent that only started was not reported running"; S=1; }
# aborted = dead - break: ignoring the aborted line, which leaves a dead agent running
printf '%s\n' "$JOUT" | grep -q "^dead     c3c3c3c3" \
  || { fail journal "an aborted agent was not reported dead"; S=1; }
# and it stays cheap - break: printing the return values, which is what the file
# already does and what this call exists not to do
printf '%s\n' "$JOUT" | grep -q TAILMARK \
  && { fail journal "the status printed a return value in full"; S=1; }
# the one result worth the tokens is still reachable - break: no way to read a
# result without reading every other one with it
"$BIN/forge-journal" --result a1a1 "$WF/wf_a" | grep -q TAILMARK \
  || { fail journal "--result did not print the agent's return value"; S=1; }
# a bare call takes the run written last - break: making the caller know the path
[ "$(HOME=/nonexistent CLAUDE_CONFIG_DIR="$JRN/cfg" "$BIN/forge-journal" | head -1)" = "1 running" ] \
  || { fail journal "a bare call did not read the newest run"; S=1; }
# and a run id finds its own - break: accepting only a path
HOME=/nonexistent CLAUDE_CONFIG_DIR="$JRN/cfg" "$BIN/forge-journal" wf_a | grep -q "^1 running, 1 done, 1 dead" \
  || { fail journal "a run id did not resolve to its journal"; S=1; }
# a run with no journal is an answer, not a crash - break: an empty output or a stack trace
MISS="$(HOME=/nonexistent CLAUDE_CONFIG_DIR=/nonexistent "$BIN/forge-journal" wf_gone 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ -n "$MISS" ] \
  || { fail journal "a missing journal did not answer in one line"; S=1; }
# an unknown flag is not a status - break: a typo reading as a run that is done
("$BIN/forge-journal" --nope >/dev/null 2>&1); [ $? = 2 ] \
  || { fail journal "an unknown flag did not exit 2"; S=1; }
[ "$S" = 0 ] && ok "journal status"

exit "$FAILED"
