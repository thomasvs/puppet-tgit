class tgit::install {
  package { 'git':
    ensure => present,
  }
}
