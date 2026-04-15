-- tests/test_normalize_github_url.lua
-- Smoke tests for _date_modified.url.normalize_github_url.
--
-- These cases encode regressions and edge cases that previously caused
-- "Unable to resolve link target" warnings on every rendered page when
-- the git remote did not match the canonical HTTPS pattern.

require("proxy")
local lu = require("luaunit")

local url_utils = require("_date_modified.url")
local normalize = url_utils.normalize_github_url

TestNormalizeGithubUrl = {}

-- ---------------------------------------------------------------------------
-- HTTPS canonical forms
-- ---------------------------------------------------------------------------

function TestNormalizeGithubUrl:test_https_without_suffix()
  lu.assertEquals(
    normalize("https://github.com/narineneoldu/narineneoldu.github.io"),
    "https://github.com/narineneoldu/narineneoldu.github.io"
  )
end

function TestNormalizeGithubUrl:test_https_with_git_suffix()
  lu.assertEquals(
    normalize("https://github.com/narineneoldu/narineneoldu.github.io.git"),
    "https://github.com/narineneoldu/narineneoldu.github.io"
  )
end

function TestNormalizeGithubUrl:test_https_simple_repo()
  lu.assertEquals(
    normalize("https://github.com/octocat/Hello-World.git"),
    "https://github.com/octocat/Hello-World"
  )
end

-- ---------------------------------------------------------------------------
-- SSH on canonical github.com host
-- ---------------------------------------------------------------------------

function TestNormalizeGithubUrl:test_ssh_github_com_simple()
  lu.assertEquals(
    normalize("git@github.com:octocat/Hello-World.git"),
    "https://github.com/octocat/Hello-World"
  )
end

function TestNormalizeGithubUrl:test_ssh_github_com_dotted_repo_name()
  -- Regression: repo names with dots (e.g. user/site pages) previously
  -- broke the regex because the repo capture used [^%.]+ instead of a
  -- greedy .+ followed by an optional `.git` suffix strip.
  lu.assertEquals(
    normalize("git@github.com:narineneoldu/narineneoldu.github.io.git"),
    "https://github.com/narineneoldu/narineneoldu.github.io"
  )
end

-- ---------------------------------------------------------------------------
-- SSH with host alias (~/.ssh/config pattern for multi-identity setups)
-- ---------------------------------------------------------------------------

function TestNormalizeGithubUrl:test_ssh_alias_basic()
  lu.assertEquals(
    normalize("git@github-isezen:isezen/some-repo.git"),
    "https://github.com/isezen/some-repo"
  )
end

function TestNormalizeGithubUrl:test_ssh_alias_dotted_repo_name()
  -- The original bug this whole test file exists to catch.
  lu.assertEquals(
    normalize("git@github-narineneoldu:narineneoldu/narineneoldu.github.io.git"),
    "https://github.com/narineneoldu/narineneoldu.github.io"
  )
end

function TestNormalizeGithubUrl:test_ssh_alias_underscore()
  lu.assertEquals(
    normalize("git@github_work:acme/internal-tools.git"),
    -- underscore in host is not part of the `github-` alias pattern,
    -- so the URL is returned unchanged.
    "git@github_work:acme/internal-tools.git"
  )
end

-- ---------------------------------------------------------------------------
-- Non-GitHub URLs must be returned unchanged (safety: do not rewrite
-- GitLab/Bitbucket/etc. SSH URLs as github.com)
-- ---------------------------------------------------------------------------

function TestNormalizeGithubUrl:test_non_github_ssh_unchanged()
  lu.assertEquals(
    normalize("git@gitlab.com:group/project.git"),
    "git@gitlab.com:group/project.git"
  )
end

function TestNormalizeGithubUrl:test_non_github_https_unchanged()
  lu.assertEquals(
    normalize("https://gitlab.com/group/project.git"),
    "https://gitlab.com/group/project.git"
  )
end

-- ---------------------------------------------------------------------------
-- Empty / nil handling
-- ---------------------------------------------------------------------------

function TestNormalizeGithubUrl:test_nil_returns_nil()
  lu.assertNil(normalize(nil))
end

function TestNormalizeGithubUrl:test_empty_string_returns_nil()
  lu.assertNil(normalize(""))
end

function TestNormalizeGithubUrl:test_whitespace_is_trimmed()
  lu.assertEquals(
    normalize("  git@github.com:octocat/Hello-World.git  "),
    "https://github.com/octocat/Hello-World"
  )
end

os.exit(lu.LuaUnit.run())
