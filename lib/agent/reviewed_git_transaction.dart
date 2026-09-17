/// Git 자체의 POSIX shell alias를 이용하므로 Git for Windows에서도 같은 계약이다.
/// 모든 사용자 데이터는 alias의 위치 인자로 전달하며 스크립트에 삽입하지 않는다.
List<String> gitTransaction(String script, List<String> arguments) => [
  '-c',
  'alias.vibe-transaction=!f() {\n$script\n}; f',
  'vibe-transaction',
  ...arguments,
];

/// 현재 파일 내용을 별도 index에 담아 불변 tree로 만든다. 사용자의 index는 건드리지 않는다.
const captureReviewedTreeScript = r'''
vibe_head=$(git rev-parse HEAD) || return
vibe_dir=$(git rev-parse --absolute-git-dir) || return
vibe_index=$(mktemp "$vibe_dir/vibe-review.XXXXXX") || return
rm -f -- "$vibe_index"
trap 'rm -f -- "$vibe_index" "$vibe_index.lock"' EXIT
export GIT_INDEX_FILE="$vibe_index"
git read-tree "$vibe_head" || return
git add -A -- . || return
vibe_tree=$(git write-tree) || return
test "$(git rev-parse HEAD)" = "$vibe_head" || { echo '검토 중 HEAD가 변경되었습니다.' >&2; return 1; }
printf '%s\n%s\n' "$vibe_head" "$vibe_tree"
''';

/// 검토한 tree에서 선택 파일만 가져온다. native index lock과 ref CAS를 함께 사용한다.
/// hooks와 signing을 보존하고 hook이 승인한 tree를 바꾸면 중단한다.
const commitReviewedTreeScript = r'''
vibe_head=$1; vibe_tree=$2; vibe_branch=$3; vibe_message=$4; vibe_index_hash=$5
shift 5
test "$(git symbolic-ref --quiet HEAD)" = "$vibe_branch" || return 1
test "$(git rev-parse HEAD)" = "$vibe_head" || { echo 'HEAD가 변경되었습니다. 다시 검토하세요.' >&2; return 1; }
vibe_index=$(git rev-parse --path-format=absolute --git-path index) || return
vibe_lock="$vibe_index.lock"
(set -C; : > "$vibe_lock") 2>/dev/null || { echo '다른 Git 작업이 index를 사용 중입니다.' >&2; return 1; }
vibe_temp=$(mktemp "$vibe_index.vibe.XXXXXX") || { rm -f -- "$vibe_lock"; return 1; }
vibe_msg="$vibe_temp.message"
trap 'rm -f -- "$vibe_temp" "$vibe_temp.lock" "$vibe_msg" "$vibe_lock"' EXIT
test "$(git hash-object -- "$vibe_index")" = "$vibe_index_hash" || { echo '검토 후 stage 상태가 변경되었습니다.' >&2; return 1; }
rm -f -- "$vibe_temp"
export GIT_INDEX_FILE="$vibe_temp"
git read-tree "$vibe_head" || return
git --literal-pathspecs restore --source="$vibe_tree" --staged -- "$@" || return
vibe_commit_tree=$(git write-tree) || return
vibe_merge_path=$(git rev-parse --path-format=absolute --git-path MERGE_HEAD) || return
vibe_merge_head=''
if test -f "$vibe_merge_path"; then
  vibe_merge_head=$(cat "$vibe_merge_path") || return
  git cat-file -e "$vibe_merge_head^{commit}" || return
  test "$vibe_commit_tree" = "$vibe_tree" || { echo '병합 커밋은 검토한 전체 변경을 선택해야 합니다.' >&2; return 1; }
fi
test -n "$vibe_merge_head" || test "$vibe_commit_tree" != "$(git rev-parse "$vibe_head^{tree}")" || { echo '선택한 파일에 변경이 없습니다.' >&2; return 1; }
printf '%s\n' "$vibe_message" > "$vibe_msg" || return
vibe_run_hook() {
  vibe_hook_name=$1; shift
  vibe_hook_dir=$(git rev-parse --path-format=absolute --git-path hooks) || return 1
  vibe_hook_path="$vibe_hook_dir/$vibe_hook_name"
  test -x "$vibe_hook_path" || return 0
  "$vibe_hook_path" "$@"
}
vibe_run_hook pre-commit || return
if test -n "$vibe_merge_head"; then
  vibe_run_hook prepare-commit-msg "$vibe_msg" merge || return
else
  vibe_run_hook prepare-commit-msg "$vibe_msg" message || return
fi
vibe_run_hook commit-msg "$vibe_msg" || return
test "$(git write-tree)" = "$vibe_commit_tree" || { echo 'Git hook이 검토한 내용을 변경했습니다. 다시 검토하세요.' >&2; return 1; }
test "$(git symbolic-ref --quiet HEAD)" = "$vibe_branch" || return 1
set -- -p "$vibe_head"
if test -n "$vibe_merge_head"; then
  test "$(cat "$vibe_merge_path")" = "$vibe_merge_head" || return 1
  set -- "$@" -p "$vibe_merge_head"
fi
if test "$(git config --bool commit.gpgsign)" = true; then
  vibe_commit=$(git commit-tree -S "$vibe_commit_tree" "$@" -F "$vibe_msg") || return
else
  vibe_commit=$(git commit-tree "$vibe_commit_tree" "$@" -F "$vibe_msg") || return
fi
git update-ref -m "commit: $vibe_message" "$vibe_branch" "$vibe_commit" "$vibe_head" || return
mv -f -- "$vibe_temp" "$vibe_index" || { echo '커밋은 생성됐지만 index 갱신에 실패했습니다. Git 상태를 확인하세요.' >&2; return 1; }
if test -n "$vibe_merge_head"; then
  rm -f -- "$vibe_merge_path" "$(git rev-parse --git-path MERGE_MSG)" "$(git rev-parse --git-path MERGE_MODE)" "$(git rev-parse --git-path AUTO_MERGE)"
fi
rm -f -- "$vibe_lock"
export GIT_INDEX_FILE="$vibe_index"
vibe_run_hook post-commit >&2 || :
printf '%s\n' "$vibe_commit"
''';
