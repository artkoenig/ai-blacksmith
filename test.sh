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
