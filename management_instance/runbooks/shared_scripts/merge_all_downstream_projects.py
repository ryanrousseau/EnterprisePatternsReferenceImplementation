import json
import os
import re
import shutil
import subprocess
from urllib.parse import urlparse
import argparse

# If this script is not being run as part of an Octopus step, return variables from environment variables.
# Periods are replaced with underscores, and the variable name is converted to uppercase
if "get_octopusvariable" not in globals():
    def get_octopusvariable(variable):
        return os.environ[re.sub('\\.', '_', variable.upper())]

# If this script is not being run as part of an Octopus step, print directly to std out.
if "printverbose" not in globals():
    def printverbose(msg):
        print(msg)


def printverbose_noansi(output):
    """
    Strip ANSI color codes and print the output as verbose
    :param output: The output to print
    """
    output_no_ansi = re.sub('\x1b\[[0-9;]*m', '', output)
    printverbose(output_no_ansi)


def get_octopusvariable_quiet(variable):
    """
    Gets an octopus variable, or an empty string if it does not exist.
    :param variable: The variable name
    :return: The variable value, or an empty string if the variable does not exist
    """
    try:
        return get_octopusvariable(variable)
    except:
        return ''


def init_argparse():
    """
    init_argparse does triple duty. It supports running the script as a regular CLI command, supports running the
    script in the context of a plain script step, and supports the script when embedded in a step template. This is
    why the values of all arguments are sourced from Octopus variables, and why we source from two styles of variables:
    regular project variables and prefixed step template variables.
    """
    parser = argparse.ArgumentParser(
        usage='%(prog)s [OPTION] [FILE]...',
        description='Find conflicts between Git repos'
    )
    parser.add_argument('--cac-username',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Credentials.Username') or get_octopusvariable_quiet(
                            'FindConflicts.Git.Credentials.Username'),
                        help='The Git username')
    parser.add_argument('--cac-password',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Credentials.Password') or get_octopusvariable_quiet(
                            'FindConflicts.Git.Credentials.Password'),
                        help='The Git password')
    parser.add_argument('--git-protocol',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Url.Protocol') or get_octopusvariable_quiet(
                            'FindConflicts.Git.Url.Protocol'),
                        help='The Git protocol (http or https)')
    parser.add_argument('--git-host',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Url.Host') or get_octopusvariable_quiet(
                            'FindConflicts.Git.Url.Host'),
                        help='The Git hostname (e.g. github.com or gitlab.com)')
    parser.add_argument('--git-organization',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Url.Organization') or get_octopusvariable_quiet(
                            'FindConflicts.Git.Url.Organization'),
                        help='The Git organization')
    parser.add_argument('--template-repo',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Url.Template') or get_octopusvariable_quiet(
                            'FindConflicts.Git.Url.Template'),
                        help='The name of the repository holding the upstream template project')
    parser.add_argument('--terraform-backend-type',
                        action='store',
                        default=get_octopusvariable_quiet('Terraform.Backend.Type') or get_octopusvariable_quiet(
                            'FindConflicts.Terraform.Backend.Type'),
                        help='The Terraform backend holding the state of downstream projects')
    parser.add_argument('--terraform-backend-init-1',
                        action='store',
                        default=get_octopusvariable_quiet('Terraform.Backend.Init1') or get_octopusvariable_quiet(
                            'FindConflicts.Terraform.Backend.Init1'),
                        help='The first additional argument to pass to "terraform init", usually the "-backend-config" arguments required to connect to a custom backend')
    parser.add_argument('--terraform-backend-init-2',
                        action='store',
                        default=get_octopusvariable_quiet('Terraform.Backend.Init2') or get_octopusvariable_quiet(
                            'FindConflicts.Terraform.Backend.Init2'),
                        help='The second additional argument to pass to "terraform init", usually the "-backend-config" arguments required to connect to a custom backend')
    parser.add_argument('--terraform-backend-init-3',
                        action='store',
                        default=get_octopusvariable_quiet('Terraform.Backend.Init3') or get_octopusvariable_quiet(
                            'FindConflicts.Terraform.Backend.Init3'),
                        help='The third additional argument to pass to "terraform init", usually the "-backend-config" arguments required to connect to a custom backend')
    parser.add_argument('--terraform-backend-init-4',
                        action='store',
                        default=get_octopusvariable_quiet('Terraform.Backend.Init4') or get_octopusvariable_quiet(
                            'FindConflicts.Terraform.Backend.Init4'),
                        help='The fourth additional argument to pass to "terraform init", usually the "-backend-config" arguments required to connect to a custom backend')
    parser.add_argument('--terraform-backend-init-5',
                        action='store',
                        default=get_octopusvariable_quiet('Terraform.Backend.Init5') or get_octopusvariable_quiet(
                            'FindConflicts.Terraform.Backend.Init5'),
                        help='The fifth additional argument to pass to "terraform init", usually the "-backend-config" arguments required to connect to a custom backend')
    parser.add_argument('--mainline-branch',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Branch.MainLine') or get_octopusvariable_quiet(
                            'ForkGiteaRepo.Git.Branch.MainLine'),
                        help='The branch name to use for the fork. Defaults to "main".')

    return parser.parse_known_args()


parser, _ = init_argparse()

backend = re.sub('[^a-zA-Z0-9]', '_', get_octopusvariable('Octopus.Project.Name').lower())
template_repo_name = parser.template_repo or re.sub('[^a-zA-Z0-9]', '_',
                                                    get_octopusvariable('Octopus.Project.Name').lower())
template_repo_url = parser.git_protocol + '://' + parser.git_host + '/' + parser.git_organization + '/' + template_repo_name + '.git'
template_repo = parser.git_protocol + '://' + parser.cac_username + ':' + parser.cac_password + '@' + parser.git_host + '/' + parser.git_organization + '/' + template_repo_name + '.git'
branch = parser.mainline_branch or 'main'
project_dir = '.octopus/project'
tenant_name = get_octopusvariable("Octopus.Deployment.Tenant.Name")


def execute(args, cwd=None, env=None, print_args=None, print_output=printverbose_noansi):
    """
        The execute method provides the ability to execute external processes while capturing and returning the
        output to std err and std out and exit code.
    """
    process = subprocess.Popen(args,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE,
                               text=True,
                               cwd=cwd,
                               env=env)
    stdout, stderr = process.communicate()
    retcode = process.returncode

    if print_args is not None:
        print_output(' '.join(args))

    if print_output is not None:
        print_output(stdout)
        print_output(stderr)

    return stdout, stderr, retcode


def init_git():
    # Set some default user details
    execute(['git', 'config', '--global', 'user.email', 'octopus@octopus.com'])
    execute(['git', 'config', '--global', 'user.name', 'Octopus Server'])


def init_terraform(parser):
    backend_type = parser.terraform_backend_type or 'pg'
    with open('backend.tf', 'w') as f:
        f.write(f"""
        terraform {{
            backend "{backend_type}" {{
          }}
          required_providers {{
            octopusdeploy = {{ source = "OctopusDeployLabs/octopusdeploy", version = "0.12.7" }}
          }}
        }}
        """)

    # Allow all the init args to be supplied as variables
    custom_args = [x for x in
                   [parser.terraform_backend_init_1, parser.terraform_backend_init_2, parser.terraform_backend_init_3,
                    parser.terraform_backend_init_4, parser.terraform_backend_init_5] if x != '']
    backend = re.sub('[^a-zA-Z0-9]', '_', get_octopusvariable('Octopus.Project.Name').lower())
    # Use default values that make sense for the reference implementation if no custom values are provided
    init_args = custom_args or [
        '-backend-config=conn_str=postgres://terraform:terraform@terraformdb:5432/' + backend + '?sslmode=disable']
    full_init_args = ['terraform', 'init', '-no-color'] + init_args
    execute(full_init_args)


def merge_repo(trimmed_workspace):
    execute(['git', 'merge', 'upstream-' + branch], cwd=trimmed_workspace)
    execute(['git', 'merge', '--continue'], cwd=trimmed_workspace, env=dict(os.environ, GIT_EDITOR="/bin/true"))

    _, _, diff_result = execute(['git', 'diff', '--quiet', '--exit-code', '@{upstream}'], cwd=trimmed_workspace)
    if diff_result != 0:
        execute(['git', 'push', 'origin'], cwd=trimmed_workspace)
        print('Changes merged successfully')
    else:
        print('No changes found.')


def find_downstream_projects(parser, merge_repo_callback):
    workspaces, _, _ = execute(['terraform', 'workspace', 'list'])
    workspaces = workspaces.replace('*', '').split('\n')

    for workspace in workspaces:
        trimmed_workspace = workspace.strip()

        if trimmed_workspace == "default" or trimmed_workspace == "":
            continue

        execute(['terraform', 'workspace', 'select', trimmed_workspace])

        octopus_space_name, _, server_retcode = execute(['terraform', 'output', '-raw', 'octopus_space_name'])

        # We only work on the projects associated with the current tenant
        if not octopus_space_name == tenant_name:
            continue

        state_json, _, _ = execute(['terraform', 'show', '-json'])
        state = json.loads(state_json)

        resources = [x for x in state.get('values', {}).get('root_module', {}).get('resources', {}) if
                     x.get('type', '') == 'octopusdeploy_project']

        for resource in resources:
            git_settings = resource.get('values', {}).get('git_library_persistence_settings', [{}])
            url = git_settings[0].get('url', None) if len(git_settings) != 0 else None
            space_id = resource.get('values', {}).get('space_id', None)
            name = resource.get('values', {}).get('name', None)

            if url is not None:
                try:
                    os.mkdir(trimmed_workspace)

                    parsed_url = urlparse(url)
                    url_with_creds = parsed_url.scheme + '://' + parser.cac_username + ':' + parser.cac_password + '@' + \
                                     parsed_url.netloc + parsed_url.path

                    execute(['git', 'clone', url_with_creds, trimmed_workspace])
                    execute(['git', 'remote', 'add', 'upstream', template_repo], cwd=trimmed_workspace)
                    execute(['git', 'fetch', '--all'], cwd=trimmed_workspace)
                    execute(['git', 'checkout', '-b', 'upstream-' + branch, 'upstream/' + branch],
                            cwd=trimmed_workspace)

                    if branch != 'master' and branch != 'main':
                        execute(['git', 'checkout', '-b', branch, 'origin/' + branch], cwd=trimmed_workspace)
                    else:
                        execute(['git', 'checkout', branch], cwd=trimmed_workspace)

                    merge_base, _, _ = execute(['git', 'merge-base', branch, 'upstream-' + branch],
                                               cwd=trimmed_workspace)
                    merge_source_current_commit, _, _ = execute(['git', 'rev-parse', 'upstream-' + branch],
                                                                cwd=trimmed_workspace)
                    _, _, merge_result = execute(['git', 'merge', '--no-commit', '--no-ff', 'upstream-' + branch],
                                                 cwd=trimmed_workspace)

                    if merge_base == merge_source_current_commit:
                        print('Project ' + str(name or '') + ' in space ' + str(
                            octopus_space_name or '') + ' is up to date')
                    elif merge_result != 0:
                        print('Project ' + str(name or '') + ' in space ' + str(octopus_space_name or '') +
                              ' has merge conflicts and has not been processed')
                        printverbose('To resolve the conflicts, run the following commands:')
                        printverbose('mkdir cac')
                        printverbose('cd cac')
                        printverbose('git clone ' + url + ' .')
                        printverbose('git remote add upstream ' + template_repo_url)
                        printverbose('git fetch --all')
                        printverbose('git checkout -b upstream-' + branch + ' upstream/' + branch)
                        if branch != 'master' and branch != 'main':
                            printverbose('git checkout -b ' + branch + ' origin/' + branch)
                        else:
                            printverbose('git checkout ' + branch)
                        printverbose('git merge-base ' + branch + ' upstream-' + branch)
                        printverbose('git merge --no-commit --no-ff upstream-' + branch)
                    else:
                        print('Project ' + str(name or '') + ' in space ' + str(octopus_space_name or '') +
                              ' is being merged with the upstream repo')

                        merge_repo_callback(trimmed_workspace)
                finally:
                    shutil.rmtree(trimmed_workspace)


print("Merging upstream template into downstream projects.")
print("Verbose logs contain instructions for resolving merge conflicts.")
init_git()
init_terraform(parser)
find_downstream_projects(parser, merge_repo)
