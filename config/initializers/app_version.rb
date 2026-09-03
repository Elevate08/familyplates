# The version shown in the admin footer and reported by anyone asking "which
# build is this?". Read once at boot from the VERSION file, which is the single
# place the number is bumped - the git tag and the CHANGELOG heading must match
# it at release time.
#
# A file rather than a git describe: the Docker image has no .git directory, and
# a version that reads "unknown" exactly where it is needed most is no use.
module HomeMealPlanner
  VERSION_FILE = Rails.root.join("VERSION")

  VERSION = begin
    raw = File.read(VERSION_FILE).strip
    raise "VERSION must be a semver number like 1.2.0, got #{raw.inspect}" unless raw.match?(/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\z/)

    raw
  rescue Errno::ENOENT
    raise "VERSION file is missing at #{VERSION_FILE}. It is the source of the app's version number."
  end
end
