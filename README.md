
# pull-request-code-coverage


A continuous integration plugin to allow detecting code coverage for only the lines changed in a PR.

Sometimes when working to get a repo to an acceptable level of code coverage, it can be hard to tell if one change is
covered enough.  This plugin will look at just the lines changed in the PR and report code coverage for only those
lines.

This plugin will output the coverage details to the CI/CD step's console. A  sample [Vela](https://github.com/go-vela) step console 

![ ](./images/vela-step-console-pr-code-coverage.png)


This plugin  as well as has the ability to comment on the PR with a summary of the coverage details.
![ ](./images/github_pr_coverage.png)


Currently, this plugin supports two coverage file format.
* jacoco for jvm based languages like java,kotlin,scala
* cobertura can be used for golang projects using [gocov-xml](https://github.com/AlekSi/gocov-xml) utility

This plugin works out of the box with [Vela](https://github.com/go-vela) (a CI/CD platform open-sourced by Target), [GitHub Actions](#github-actions-usage), and any CI that can run a container.

## VELA Usage

### Jvm based projects
For java/koltin based projects you need jacoco files that goes as an input to this plugin. How to generate jacoco files is outside the scope of
this project. Once you have that jacoco file, you can pass that path to coverage_file parameter as shown  below

```yaml
- name: check-pr-code-coverage
   image: docker.target.com/app/pull-request-code-coverage
   pull: true
   ruleset:
     event: [pull_request]
   parameters:
     coverage_type: jacoco
     coverage_file: some-sub-module/build/reports/jacoco/test/jacocoTestReport.xml
     source_dirs:
       - src/main/java
       - src/main/kotlin
     # omit for public github.com (defaults to https://api.github.com)
     # for GitHub Enterprise, use the full API root including /api/v3
     gh_api_base_url: https://git.target.com/api/v3
     module: some-sub-module
   secrets:
     - source: pull_request_api_key
       target: plugin_gh_api_key
```


### Golang based projects
You can use [gocov-xml](https://github.com/AlekSi/gocov-xml) utility to generate coverage.xml
```
 - go get github.com/axw/gocov/gocov
 - go get github.com/AlekSi/gocov-xml
 - go test -v -coverpkg=./... -coverprofile=coverage.txt ./...
 - go tool cover -func=coverage.txt
 - gocov convert coverage.txt | gocov-xml > ./coverage.xml
```

Once you have coverage.xml same can  be passed as an input to plugin shown below

```yaml
- name: check-pr-code-coverage
   image: docker.target.com/app/pull-request-code-coverage
   pull: true
   ruleset:
     event: [pull_request]
   parameters:
     coverage_type: cobertura
     #coverage.xml generated in above step
     coverage_file: coverage.xml
     source_dirs:
       - /vela/src/github.com/targetOSS/pull-request-code-coverage
     # omit for public github.com (defaults to https://api.github.com)
     # for GitHub Enterprise, use the full API root including /api/v3
     gh_api_base_url: https://git.target.com/api/v3
   secrets:
     - source: pull_request_api_key
       target: plugin_gh_api_key
```

#### Parameters

|param|required| default | description|
|---|---|---|---|
|coverage_type| true | | **supported values**: jacoco, cobertura<br><br>sets the coverage file format  |
|coverage_file| true | | path to where the coverage file will be located, relative to the working dir |
|source_dirs| true | | array of source dirs, relative to the working dir |
|gh_api_base_url| false | | base url of the gh api for posting coverage comments<br><br>if not set, coverage details will not be commented on PR   |
|gh_api_key| false | | api key to auth for posting coverage comments<br><br>if not set, coverage details will not be commented on PR  |
|module | false  | \<empty string\> | sub-module to use if operating inside a multi-module project (e.g. gradle multi-project build) |

## GitHub Actions Usage

On GitHub Actions you generate the coverage report in a step, then run the plugin
image with the PR diff piped to its stdin. Posting the comment uses the built-in
`GITHUB_TOKEN`, so the job needs `pull-requests: write`.

Leave the base URL unset for public github.com (it defaults to
`https://api.github.com`). For GitHub Enterprise set `PARAMETER_GH_API_BASE_URL`
to your API root, e.g. `https://git.example.com/api/v3`.

### Go (cobertura)

[gocover-cobertura](https://github.com/boumenot/gocover-cobertura) converts a Go
coverage profile to cobertura in a single step (run via `go run`, nothing to install).

```yaml
name: pr-code-coverage
on:
  pull_request:

permissions:
  contents: read
  pull-requests: write

jobs:
  coverage:
    runs-on: ubuntu-latest
    # GITHUB_TOKEN is read-only on fork PRs, so restrict to same-repo PRs.
    if: github.event.pull_request.head.repo.full_name == github.repository
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # need the base branch present to diff against

      - uses: actions/setup-go@v5
        with:
          go-version: '1.26'

      - name: Generate coverage profile
        run: go test -coverpkg=./... -coverprofile=coverage.txt ./...

      - name: Convert to cobertura
        run: go run github.com/boumenot/gocover-cobertura@latest < coverage.txt > coverage.xml

      - name: Report coverage on changed lines
        env:
          PARAMETER_COVERAGE_TYPE: cobertura
          PARAMETER_COVERAGE_FILE: coverage.xml
          # Must equal the absolute path in the cobertura <source> element,
          # which gocover-cobertura sets to the dir `go test` ran in.
          PARAMETER_SOURCE_DIRS: ${{ github.workspace }}
          PARAMETER_GH_API_KEY: ${{ secrets.GITHUB_TOKEN }}
          BUILD_PULL_REQUEST_NUMBER: ${{ github.event.pull_request.number }}
          REPOSITORY_ORG: ${{ github.repository_owner }}
          REPOSITORY_NAME: ${{ github.event.repository.name }}
        run: |
          git fetch --no-tags origin "${{ github.base_ref }}"
          git --no-pager diff --unified=0 "origin/${{ github.base_ref }}" -- '*.go' \
            | docker run --rm -i \
                -e PARAMETER_COVERAGE_TYPE -e PARAMETER_COVERAGE_FILE \
                -e PARAMETER_SOURCE_DIRS -e PARAMETER_GH_API_KEY \
                -e BUILD_PULL_REQUEST_NUMBER -e REPOSITORY_ORG -e REPOSITORY_NAME \
                -v "${{ github.workspace }}:${{ github.workspace }}" \
                -w "${{ github.workspace }}" \
                --entrypoint /plugin \
                pullrequestcc/pull-request-code-coverage:latest
```

For JVM projects, generate a jacoco report instead and set
`PARAMETER_COVERAGE_TYPE=jacoco`, `PARAMETER_COVERAGE_FILE` to the jacoco XML, and
`PARAMETER_SOURCE_DIRS` to your source dir(s) (e.g. `src/main/java`).

### Environment variables

Outside Vela, configure the plugin with these environment variables (Vela's
`parameters:` map to the same `PARAMETER_*` names automatically):

| variable | required | description |
|---|---|---|
| `PARAMETER_COVERAGE_TYPE` | yes | `jacoco` or `cobertura` |
| `PARAMETER_COVERAGE_FILE` | yes | path to the coverage report |
| `PARAMETER_SOURCE_DIRS` | yes | comma-separated source dirs (see the cobertura `<source>` note above) |
| `PARAMETER_MODULE` | no | sub-module path in a multi-module project |
| `PARAMETER_GH_API_KEY` | no | token used to post the PR comment (`GITHUB_TOKEN` on Actions); `PLUGIN_GH_API_KEY` is also accepted. If unset, results only print to the console |
| `PARAMETER_GH_API_BASE_URL` | no | GitHub API root; defaults to `https://api.github.com`. For Enterprise use `https://HOST/api/v3` |
| `PARAMETER_DEBUG` | no | `true` for verbose path-matching logs |
| `BUILD_PULL_REQUEST_NUMBER` | no\* | PR number to comment on |
| `REPOSITORY_ORG` | no\* | repository owner |
| `REPOSITORY_NAME` | no\* | repository name |

\* required together for the PR comment; if any is missing the plugin only prints to the console.

### Using the container entrypoint directly

The image's default entrypoint (`scripts/start.sh`) can compute the diff for you
in any CI or a plain `docker run`. Point it at the target branch and it fetches,
diffs, and pipes the result to the plugin:

| variable | description |
|---|---|
| `PARAMETER_TARGET_BRANCH` | branch to diff against (Vela uses `VELA_PULL_REQUEST_TARGET` as a fallback) |
| `PARAMETER_RUN_DIR` | directory containing the `plugin` binary (default: image root) |
| `GIT_NETRC_MACHINE` / `GIT_NETRC_USERNAME` / `GIT_NETRC_PASSWORD` | optional `~/.netrc` git auth for private remotes (Vela uses `VELA_NETRC_*`) |

# Development

This project needs  go (>= 1.26.3) to be  installed. Make sure you run
* make format
* make lint 

 before submitting a PR

# License
This project is licensed under the Apache License, Version 2.0.