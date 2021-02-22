# = Define: tgit::checkout
#
# This define maintains a git checkout from a repository.
# known_hosts and ssh identities should be set up properly.
#
# To express a dependency on checkoutdir, use:
#   require => Exec["git-clone-${directory}/${checkoutdir}"]
# This define will require the passed $directory.

#
# == Parameters:
#
# $directory::   The directory in which to run the initial clone command.
#                This define will drop a file called $commit_file to track the
#                last requested commit to avoid updates.
# $checkoutdir:: The directory to clone into.  You can use '.' to have it
#                go in $directory.
# $repository::  The URL to the repository.
# $user::        The user to clone or update as
# $commit::      The commit hash, branch or tag to check out.
#                For remote branches, use origin/(name) notation
# $commit_file:: The name of the file that tracks the commit hash
# $manage_directory:: If true, this define creates the File resource for
#                     the given directory.
#
# == Actions:
#   Clone and checkout or update to a given commit or tag.
#
# == Sample Usage:
#
#   tgit::checkout {'linux kernel':
#       directory => '/usr/src',
#       checkoutdir => 'linux',
#       repository => 'git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux-2.6.git',
#       commit => 'v3.2',
#   }
#
define tgit::checkout (
  $directory,
  $checkoutdir,
  $repository,
  $user=undef,
  $commit='master',
  $commit_file='commit',
  $manage_directory=true,
  $ensure='present',
) {

  include tgit::install

  if ($manage_directory) {
    file { $directory:
      ensure => $ensure ? { 'absent' => 'absent', default => directory },
      mode   => '0755',
      owner  => $user,
    }
  }

  $allrequire = [
    File[$directory],
    Class['tgit::install'],
  ]

  if ($user) {
    $myrequire = [$allrequire, User[$user], ]
  } else {
    $myrequire = [$allrequire, ]
  }

  # only run if the .git directory does not exist
  if ($ensure == 'present') {
    exec { "git-clone-${directory}/${checkoutdir}":
      cwd         => $directory,
      user        => $user,
      path        => [ '/bin', '/usr/bin', ],
      command     => "git clone --recursive ${repository} ${checkoutdir} && cd ${checkoutdir} && git checkout ${commit}",
      creates     => [
        "${directory}/${checkoutdir}",
        "${directory}/${checkoutdir}/.git",
      ],
      refreshonly => false,
      logoutput   => on_failure,
      require     => $myrequire,
    }

    # FIXME: only run if the commit is given and different from current checkout
    # FIXME: but if we check out a branch, always fetch and update
    # FIXME: if it's a branch, we need to do git pull too
    exec { "git-checkout-${directory}/${checkoutdir}":
      cwd         => "${directory}/${checkoutdir}",
      user        => $user,
      path        => [ '/bin', '/usr/bin', ],
      refreshonly => false,
      logoutput   => on_failure,
      require     => Exec["git-clone-${directory}/${checkoutdir}"],
      # Note:
      # $commit can be
      # - a local branch (which will not be updated)
      # - a remote branch (which will be updated)
      # - a tag (tags are fetched so will be recent)
      # - a commit hash

      # to keep updating from a branch, use origin/(branch name)
      # FIXME: if git pull creates new files that are already present,
      #        a pull fails, and so we don't have newer commits
      #        so instead we fetch, then do a detached checkout of
      #        $commit, and since git checkout has --force it overwrites
      #        those files
      command     => "git fetch -a \
        && git fetch -t \
        && git checkout --force ${commit} \
        && git submodule init \
        && git submodule sync \
        && git submodule update --recursive \
        && git rev-parse HEAD > ../${commit_file}",

      # if the unless command has an exit value of 1, command will run

      # if there is no commit file, run
      # if there is a commit file, but it matches $commit (and hence is
      # an actual commit hash), don't run
      # if commit is master or a branch name, we need to fetch because
      #    origin may have changed
      # run if whatever commit hash the $commit points to does not match
      #    our current commit file

      # test on machine with:
      # su - www
      # cd /var/www/checkout
      # export commit=master
      # copy-paste unless command
      # echo $?
      unless      => "test -e ../${commit_file} && \
        ( \
        test x${commit} == `cat ../${commit_file}` || \
        ( \
        git fetch -a; \
        test `git rev-parse --verify ${commit}^0 | head -n 1` == `cat ../${commit_file}` ) )",
    }
  }
}
