#!/usr/bin/env bash
# Every check that runs without a Claude Code session.
# Prints one line per suite. A failure prints "FAIL <suite>: <what>".
set -uo pipefail
cd "$(dirname "$0")"

FAILED=0
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAILED=1; }
ok()   { printf 'ok   %s\n' "$1"; }

# --- manifest and syntax ----------------------------------------------------
if command -v claude >/dev/null && ! claude plugin validate ./plugins/forge --strict >/dev/null 2>&1; then
  fail manifest "claude plugin validate rejected plugins/forge"
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
  "compaction": { "maxLines": 10, "headLines": 4, "tailLines": 2 } }
JSON
cat > "$FIX/fake.sh" <<'JSON'
echo "  ✕ rejects an expired token"
echo "     expected 401, received 200"
exit 1
JSON
export CLAUDE_PROJECT_DIR="$FIX"
BIN="$PWD/plugins/forge/bin"

# --- wrapper contract -------------------------------------------------------
S=0
[ "$(cd "$FIX" && "$BIN/forge-test")" = "1" ] || { fail wrappers "bare forge-test did not print 1"; S=1; }
[ "$(cd "$FIX" && "$BIN/forge-test" --failing)" = "rejects an expired token" ] \
  || { fail wrappers "--failing did not name the failing test"; S=1; }
(cd "$FIX" && "$BIN/forge-test" --detail "rejects an expired token") | grep -q "expected 401" \
  || { fail wrappers "--detail did not show the failure"; S=1; }
(cd "$FIX" && "$BIN/forge-lint" 2>&1) | grep -q "^unconfigured" \
  || { fail wrappers "an unconfigured command did not say so"; S=1; }
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

# --failing answers for the last run, not for whatever the log says. A passing
# run whose output carries "error" or matches failingPattern has no ids.
PASSFIX="$(mktemp -d)"
trap 'rm -rf "$FIX" "$PASSFIX"' EXIT
mkdir -p "$PASSFIX/.forge"
cat > "$PASSFIX/.forge/config.json" <<'JSON'
{ "commands": { "test": { "command": "bash ./fake.sh", "parser": "generic",
                          "failingPattern": "E[0-9]+" } } }
JSON
cat > "$PASSFIX/fake.sh" <<'SH'
echo "warn: E42 error recovered, 0 failures"
exit 0
SH
[ "$(cd "$PASSFIX" && CLAUDE_PROJECT_DIR="$PASSFIX" "$BIN/forge-test")" = "0" ] \
  || { fail wrappers "the passing fixture did not print 0"; S=1; }
# AC1 - passing run, log matches failingPattern -> none.
[ "$(cd "$PASSFIX" && CLAUDE_PROJECT_DIR="$PASSFIX" "$BIN/forge-test" --failing)" = "none" ] \
  || { fail wrappers "--failing invented ids after a passing run"; S=1; }
# AC3 - no log yet, and the run it triggers passes -> none.
rm -rf "$PASSFIX/.forge/last"
[ "$(cd "$PASSFIX" && CLAUDE_PROJECT_DIR="$PASSFIX" "$BIN/forge-test" --failing)" = "none" ] \
  || { fail wrappers "--failing did not run the passing command itself"; S=1; }
# AC3 - no log yet, and the run it triggers fails -> that run's ids.
rm -rf "$FIX/.forge/last"
[ "$(cd "$FIX" && "$BIN/forge-test" --failing)" = "rejects an expired token" ] \
  || { fail wrappers "--failing did not run the failing command itself"; S=1; }
# AC2 - a failing run keeps naming its ids on a second call.
[ "$(cd "$FIX" && "$BIN/forge-test" --failing)" = "rejects an expired token" ] \
  || { fail wrappers "--failing lost the ids of a failing run"; S=1; }
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
node -e '
  const l=[...Array(30)].map((_,i)=>"line "+i).join("\n")
  process.stdout.write(JSON.stringify({tool_use_id:"t",tool_response:{stdout:l,stderr:"boom",interrupted:false,isImage:false}}))
' | node plugins/forge/scripts/compact-output.js | node -e '
  let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
    const o=JSON.parse(s).hookSpecificOutput.updatedToolOutput
    if(o.stdout.split("\n").length!==7) {console.log("wrong line count");process.exit(1)}
    if(o.stderr!=="boom") {console.log("stderr was touched");process.exit(1)}
  })' || { fail hooks "compact-output did not compact correctly"; S=1; }
[ -z "$(hook compact-output.js '{"tool_response":{"stdout":"one\ntwo","stderr":"","interrupted":false,"isImage":false}}')" ] \
  || { fail hooks "compact-output touched a short result"; S=1; }
[ "$S" = 0 ] && ok "hook decisions"

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

S=0
echo '{"cwd":"'"$CTX"'","session_id":"s1","agent_id":"a1","agent_type":"forge:prober"}' \
  | CLAUDE_PROJECT_DIR="$CTX" node plugins/forge/scripts/subagent-start.js >/dev/null
echo '{"cwd":"'"$CTX"'","session_id":"s1","agent_id":"a1","agent_type":"forge:prober","transcript_path":"'"$CTX/t/s1.jsonl"'"}' \
  | CLAUDE_PROJECT_DIR="$CTX" node plugins/forge/scripts/subagent-metrics.js >/dev/null
echo '{"cwd":"'"$CTX"'","session_id":"s1","agent_id":"a2","agent_type":"forge:prober","transcript_path":"'"$CTX/t/s1.jsonl"'"}' \
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
    [ "$(wc -l < "$f")" -le 40 ] || { fail areas "$f is past the 40 line budget for a note"; S=1; }
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
  const agent=async(prompt,o)=>{
    calls.push(o.label)
    if(o.label.startsWith('prepare')) return {branch:'forge/1',base:'b0'}
    if(o.label.startsWith('merge')){
      const ids=[...prompt.matchAll(/^ {2}(\S+): /gm)].map(m=>m[1])
      return {results:ids.map(id=>({increment:id,merged:!conflicts.includes(id),sha:'s',conflict:'x'}))}
    }
    const inc=(o.label.split(':')[1]||'').split('/')[1]||'1'
    if(/^(implement|repair)/.test(o.label)) return {status:'implemented',branch:'b',worktree:a.increments?'/wt':'',base:'b0',summary:'s'}
    if(o.label.startsWith('review')){const q=verdicts[inc]||[];return q.shift()??{pass:true,failed:[]}}
    return {committed:true,sha:'c'}
  }
  return new Function('agent','phase','log','parallel','args',`return (async () => {${src}})()`)
    (agent,()=>{},()=>{},t=>Promise.all(t.map(f=>f())),a).then(r=>({r,calls}))
}
const st=r=>Object.fromEntries((r.increments||[]).map(i=>[i.increment,i.status]))
const eq=(a,b,m)=>{if(JSON.stringify(a)!==JSON.stringify(b)){console.log(m,JSON.stringify(a));process.exit(1)}}
;(async()=>{
  let {r,calls}=await run('1')
  eq(r.status,'done','uncut issue')
  eq(calls,['prepare:1','implement:1','review:1:0','commit:1'],'uncut dispatch order')

  ;({r,calls}=await run({issue:'1',increments:[{id:'a',dependsOn:[]},{id:'b',dependsOn:[]}]}))
  eq(calls.slice(1,3),['implement:1/a','implement:1/b'],'independent increments did not run together')
  eq(st(r),{a:'merged',b:'merged'},'independent outcomes')

  ;({r,calls}=await run({issue:'1',increments:[{id:'a',dependsOn:[]},{id:'b',dependsOn:['a']}]}))
  eq(calls.indexOf('implement:1/b')>calls.indexOf('merge:1'),true,'a dependent started before its dependency merged')

  ;({r}=await run({issue:'1',increments:[{id:'a',dependsOn:[]},{id:'b',dependsOn:['a']},{id:'c',dependsOn:[]}]},
    {verdicts:{a:[{pass:false,failed:['AC1']},{pass:false,failed:['AC1']}]}}))
  eq(st(r),{a:'stalled',c:'merged',b:'skipped'},'a stall did not skip dependents while siblings merged')

  ;({r}=await run({issue:'1',increments:[{id:'a',dependsOn:[]},{id:'b',dependsOn:[]}]},{conflicts:['b']}))
  eq(st(r),{a:'merged',b:'conflicted'},'a merge conflict was not reported')

  eq((await run('')).r.status,'error','a missing issue id was accepted')
  eq((await run({issue:'1',agentPrefix:''})).r.status,'done','agentPrefix did not resolve')
})()
JS
[ "$FAILED" = 0 ] && ok "workflow control flow"

exit "$FAILED"
