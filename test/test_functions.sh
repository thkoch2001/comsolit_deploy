#!/bin/sh
#
# Copyright 2014 comsolit AG
# Released under the LGPL (GNU Lesser General Public License)

. ../lib/test_helpers
. ../src/functions.sh

testGitConfigGet() {
  local file=test_functions/general

  assertEquals "true" $(_comsolit_deploy_get_git_config $file a.bool.truish get bool)
  assertEquals "true" $(_comsolit_deploy_get_git_config $file a.bool.truish get)
  assertEquals "true" $(_comsolit_deploy_get_git_config $file a.bool.truish)

  assertEquals $(_comsolit_deploy_get_git_config $file a.bool.falsy) "false"
  assertEquals 0 $(_comsolit_deploy_get_git_config $file an.int.zero get int)
  assertEquals "0" $(_comsolit_deploy_get_git_config $file an.int.zero get int)
  assertEquals 1 $(_comsolit_deploy_get_git_config $file an.int.one get int)
  assertEquals -1 $(_comsolit_deploy_get_git_config $file an.int.minusone get int)
  assertEquals 10 $(_comsolit_deploy_get_git_config $file an.int.ten get int)

  assertEquals 0 $(_comsolit_deploy_get_git_config $file an.int.zero)
}

testGitConfigGetAll() {
  local file=test_functions/general

  assertEquals "hello world
hello git" \
    "$(_comsolit_deploy_get_git_config $file multiple.values get-all)"
}

testGitCatBlobToTmp() {
  local git_dir=test_functions/cat_blob.git
  local tmpfile
  tmpfile="$(_comsolit_deploy_cat_blob_to_tmp $git_dir "master:catblob")"

  assertEquals "hello world!!" "$(cat $tmpfile)"
  rm $tmpfile
}

testGetConfig() {
  # override global GIT_DIR
  export GIT_DIR=test_functions/cat_blob.git
  _COMSOLIT_DEPLOY_CONFIG_BLOB="master:config"

  assertEquals "foo" "$(get_config sec.tion)"
}

testGetOldCheckouts() {
  local tmpdir
  tmpdir=$(mktemp --directory --tmpdir=${SHUNIT_TMPDIR})

  touch $tmpdir/1
  touch $tmpdir/2
  touch $tmpdir/3
  touch $tmpdir/4

  assertEquals "1
2
3" \
    "$(get_old_checkouts "$tmpdir" 1)"

  assertEquals "1
2" \
    "$(get_old_checkouts "$tmpdir" 2)"

  assertEquals "1" "$(get_old_checkouts "$tmpdir" 3)"
  assertEquals "" "$(get_old_checkouts "$tmpdir" 4)"
  assertEquals "" "$(get_old_checkouts "$tmpdir" 5)"
  assertEquals "" "$(get_old_checkouts "$tmpdir" 6)"
}

testRemoveCheckouts() {
  local tmpdir
  tmpdir=$(mktemp --directory --tmpdir=${SHUNIT_TMPDIR})

  touch $tmpdir/1
  touch $tmpdir/2
  touch $tmpdir/3
  touch $tmpdir/4

  remove_old_checkouts "$tmpdir" 2

  assertEquals "3
4" \
    "$(ls -1 $tmpdir)"
}

testSwitchSymlink() {
  local tmpdir
  local checkouts_dir
  local a
  local b
  tmpdir=$(mktemp --directory --tmpdir=${SHUNIT_TMPDIR})
  checkouts_dir=$tmpdir/checkouts
  a=$checkouts_dir/2012-12-02
  b=$checkouts_dir/2013-01-12

  DEPLOY_ROOT=$tmpdir
  mkdir -p $a
  echo "a" > $a/sample
  assertEquals "a" $(cat $a/sample)
  mkdir -p $b
  echo "b" > $b/sample
  assertEquals "b" $(cat $b/sample)

  switch_symlink $a
  assertEquals "a" $(cat $DEPLOY_ROOT/current/sample)

  switch_symlink $b
  assertEquals "b" $(cat $DEPLOY_ROOT/current/sample)
}

testRunHook() {
  local tmpdir
  local out
  local hooksdir
  local hook
  tmpdir=$(mktemp --directory --tmpdir=${SHUNIT_TMPDIR})
  hooksdir=$tmpdir/.deploy/hooks
  hook=what-ever

  CHECKOUT_DIR=$tmpdir
  _COMSOLIT_LOG_INFO=true

  out=$(run_hook $hook)
  assertEquals "" "$out"

  mkdir -p $hooksdir
  out=$(run_hook $hook)
  assertEquals "" "$out"

  touch $hooksdir/$hook
  out=$(run_hook $hook)
  assertEquals "" "$out"

  chmod a+x $hooksdir/$hook
  out=$(run_hook $hook)
  assertEquals "1" "$(echo $out|wc -l)"

  echo "#!/bin/sh" >$hooksdir/$hook
  out=$(run_hook $hook)
  assertEquals "1" "$(echo $out|wc -l)"

  _COMSOLIT_LOG_INFO=""
  echo "echo washere" >>$hooksdir/$hook
  out=$(run_hook $hook)
  assertEquals "washere" "$out"
}

testDeploy() {
  local tmpdir=$(mktemp --directory --tmpdir=${SHUNIT_TMPDIR})
  local checkout_dir="2014-02-12_14-30-25-c5b140057695c3989c7ab310b61d5e54ae4901b7-"

  unset GIT_DIR
  cp -r test_functions/cat_blob.git $tmpdir
  cd $tmpdir/cat_blob.git

  COMSOLIT_TIMESTAMP="1392211825"
  deploy master "${tmpdir}"

  assertEquals "hello world!!" "$(cat ${tmpdir}/current/catblob)"
  assertEquals "hello world!!" "$(cat ${tmpdir}/checkouts/${checkout_dir}/catblob)"
  assertEquals "${checkout_dir}" "$(ls -1 ${tmpdir}/checkouts)"
}

__feedback_testDeployWithHooks_post_checkout() {
  echo "post-checkout"
  echo $@
}

__feedback_testDeployWithHooks_post_switch() {
  echo "post-switch"
  echo $@
}

testDeployWithHooks() {
  local tmpdir=$(mktemp --directory --tmpdir=${SHUNIT_TMPDIR})
  local out

  unset GIT_DIR
  cp -r test_functions/with_hooks.git $tmpdir
  cd $tmpdir/with_hooks.git

  _COMSOLIT_LOG_INFO=""
  _TEST_RUN_POST_CHECKOUT=__feedback_testDeployWithHooks_post_checkout
  _TEST_RUN_POST_SWITCH=__feedback_testDeployWithHooks_post_switch
  COMSOLIT_TIMESTAMP="1392211825"
  out=$(deploy master "${tmpdir}")
  assertEquals \
    "post-checkout master fb458699833884586b31f0e76421386998258c5b 1.0+rc2-1-gfb45869
post-switch master fb458699833884586b31f0e76421386998258c5b 1.0+rc2-1-gfb45869" \
    "${out}"
}

testOnHostingServerOnPostReceive() {
  local tmpdir=$(mktemp --directory --tmpdir=${SHUNIT_TMPDIR})
  local sourcegit=$tmpdir/with_config_deploy_root.git
  local targetgit=$tmpdir/target.git
  local out

  mkdir -p $targetgit
  git --git-dir=$targetgit init --bare --quiet
  ln -s $(readlink -f ../src/hosting_server_hook.sh) $targetgit/hooks/post-receive

  cp -r test_functions/with_config_deploy_root.git $tmpdir
  git --git-dir=$sourcegit remote add origin $targetgit
  git --git-dir=$sourcegit push --quiet origin master

  out=$(ls -1 $tmpdir/current/.deploy)
  assertEquals "config" "${out}"
}

# suite functions
oneTimeSetUp()
{
  th_oneTimeSetUp
}

setUp() {
  cd "${TH_INITIAL_CURRENT_DIRECTORY}"
}

tearDown()
{
  true
}

# load and run shUnit2
[ -n "${ZSH_VERSION:-}" ] && SHUNIT_PARENT=$0
. ${TH_SHUNIT}
