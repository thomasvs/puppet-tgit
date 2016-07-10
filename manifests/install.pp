class tgit::install {
  # this now includes ::git, the puppetlabs module, directly to avoid
  # duplicate package declaration
  include ::git
}
