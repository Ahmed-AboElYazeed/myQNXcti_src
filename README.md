# Integrating Open Source Projects / Applications into the QuickStart Custom Target Image build

## Overview

There are three sources of open source projects that are integrated into this
Quickstart Custom Target Image build:

- projects from QNX projects on Gitlab
- projects from the Internet in general
- local projects
- sample projects
- project repos

If you have followed this project since it was first introduced, you may have noticed that
some projects have been removed from this part of the build.  The reason for this is that
the components, that were previously built from source, are now installed from apk packages
with pre-built binaries.  In a future release of this project, we will provide instructions
and methodology for developers to leverage the same technology for the custom components they
want to integrate or other open source components they want to integrate into their projects.

## General Approach to Integration of Projects to Build from Source

### Common build environment

All integrations take advantage of the following features of the project:

- separate SDP installation located in the qnx800 subfolder created under the
  project root folder
- a staging folder created in this folder (named `stage`) where locally built
  binaries and artifacts are installed as the different projects are built
  (this is important for building projects to find artifacts generated from
  other projects that they are dependent on)

Similar steps apply to integrating projects from any of the four sources above:

### Add a make target to download the project called `source/<project>-ready`

Add a make target to represent downloading and, if required, unpacking the
project's source. The make target should:

- add a command to clone the repo, or a command to download the project package
- if required, add an option to clone a specific branch or add a command to
  cd into the folder and checkout a specific branch
- if downloading a package, add a command to unpackage the package
- if required, a patch may need to be applied to build the project successfully
  for QNX.  A general approach for patching includes:
  - from within the cloned project folder, make any changes required to
    successfully build the project
  - run the git diff command and save the patch in the src/patches folder
  - update the make target commands after cloning to run 'git apply' to apply
    the patch before the build commands

The target MUST create a sentinel file called `source/<project>-ready` as
its last step. While the actual project directory can be used it is not
recommended as the modification timestamp of the directory can often confuse
make.

> It is strongly recommended that a specific, explicit, version of the project
> is used instead of using whatever is the latest at time of download. That
> way things don't change behind the scenes unexpectedly.

### Add a Make target to build the project called `source/<project>-built-$(QNX_ARCH)`

Add a make target to actually build the source. The target should depend on
the sentinel file created in the last step. In addition, if this is a project
from QNX ports, `source/build-files-ready` must also be added as a dependency.
Any other project that needs to be built first, must be integrated beforehand
using a similar process as described below and its make target has to be added
as a dependency.

> **NOTE** The target may be built multiple times for different architectures.
> This target's makefile rules should be able to handle that possibility.

- consult the project build instructions and add commands to cd into the
  project folder and build the project (note that in some cases, you must make
  build folders and go into the build folders to build the project)
- add commands to install the project binaries and includes (if required) into
  the src/stage folder that represents the local installation (some projects
  "make install" commands may work properly to do this or you may need to add
  custom commands to copy to the appropriate spot)

The target MUST create a sentinel file called
`source/<project>-built-$(QNX_ARCH)` as a final step when the build completes
successfully. This represents the successful build of the target for the
current architecture in the `$(QNX_ARCH)` variable.

### Add <project> to the PKGS variable

The name of the project needs to be added to the `PKGS` variable. This will
automatically add it as a dependency of the `all` target, so that it will
be built by default.

> If you only want to build <project> in specific circumstances, only add it
> to `PKGS` when those circumstances are present.

### Update the snippets to include generated artifacts

Once the project artifacts are successfully built, note where they are located
within the `stage` directory and update the appropriate [snippets](../snippets)
files (review the README of this folder more details) to include the artifacts
built for the new project.

### Rebuild the project and check for warnings

Rebuild the project and make sure there are no warnings during image generation.
That would indicate that the recipe updates are incorrect.

### Flash / run the build image and confirm new content is present

Flash the build, or run the image, and check that the new content is present and
running properly.  Note that some open source applications expect their content
at certain locations that are not standard in the image, requiring additional recipe
updates to add symbolic links to the content to make it also available at an
expected path.

## General Approach to Integration of Sample Projects / Repos

The general approach for integrating sample projects and including project repos cloned
from public sources is similar to the source build integration, but simpler.
It only includes setting up one target to download, clone or copy the repo, optionally
apply one or more patches, and then extract or copy into the destination folder reserved
for snippets to integrate the project folders or repo.

See the examples in the Makefile and adapt accordingly for your own local sample
projects and repos you want to include in your build.

## Integrations by Category

### QNX Gitlab projects integrations

URL: [https://gitlab.com/qnx/projects](https://gitlab.com/qnx/projects)

projects:

- rpi-gpio
- rpi-mailbox
- rpi-thermal
- simple-terminal

### Internet (in general)

projects:

- thorvg

### Local Projects

projects:

- qnx-lottie_thorvg

### Sample projects

projects:

- hello_world_c
- hello_world_cpp
- hello_world_python
- Maelstrom
- python_graphviz
- python_numpty

### Project Repos

There are no repos currently included in the build.
