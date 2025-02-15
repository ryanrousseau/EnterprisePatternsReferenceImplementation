# This script previews the changes to be merged in from an upstream repo. It makes use of the diff2html
# tool. Run this script in the octopussamples/diff2html container image, which has diff2html and Python 3
# installed and ready to use.

import argparse
import subprocess
import sys
import os
import urllib.request
import base64
import re

# If this script is not being run as part of an Octopus step, createartifact is a noop
if "createartifact" not in globals():
    def createartifact(file, name):
        pass

# If this script is not being run as part of an Octopus step, print directly to std out.
if "printverbose" not in globals():
    def printverbose(msg):
        print(msg)

if "printhighlight" not in globals():
    def printhighlight(msg):
        print(msg)

# If this script is not being run as part of an Octopus step, return variables from environment variables.
# Periods are replaced with underscores, and the variable name is converted to uppercase
if "get_octopusvariable" not in globals():
    def get_octopusvariable(variable):
        return os.environ[re.sub('\\.', '_', variable.upper())]


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


def printverbose_noansi(output):
    """
    Strip ANSI color codes and print the output as verbose
    :param output: The output to print
    """
    output_no_ansi = re.sub('\x1b\[[0-9;]*m', '', output)
    printverbose(output_no_ansi)


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


def check_repo_exists(url, username, password):
    try:
        auth = base64.b64encode((username + ':' + password).encode('ascii'))
        auth_header = "Basic " + auth.decode('ascii')
        headers = {
            "Authorization": auth_header
        }
        request = urllib.request.Request(url, headers=headers)
        urllib.request.urlopen(request)
        return True
    except:
        return False


def init_argparse():
    parser = argparse.ArgumentParser(
        usage='%(prog)s [OPTION] [FILE]...',
        description='Merge the upstream repo into the downstream repo'
    )
    parser.add_argument('--original-project-name',
                        action='store',
                        default=get_octopusvariable_quiet('Octopus.Project.Name'))
    parser.add_argument('--new-project-name',
                        action='store',
                        default=get_octopusvariable_quiet('Exported.Project.Name') or get_octopusvariable_quiet(
                            'PreviewMerge.Exported.Project.Name'))
    parser.add_argument('--git-protocol',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Url.Protocol') or get_octopusvariable_quiet(
                            'PreviewMerge.Git.Url.Protocol'))
    parser.add_argument('--git-host',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Url.Host') or get_octopusvariable_quiet(
                            'PreviewMerge.Git.Url.Host'))
    parser.add_argument('--git-username',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Credentials.Username') or get_octopusvariable_quiet(
                            'PreviewMerge.Git.Credentials.Username'))
    parser.add_argument('--git-password',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Credentials.Password') or get_octopusvariable_quiet(
                            'PreviewMerge.Git.Credentials.Password'))
    parser.add_argument('--git-organization',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Url.Organization') or get_octopusvariable_quiet(
                            'PreviewMerge.Git.Url.Organization'))
    parser.add_argument('--tenant-name',
                        action='store',
                        default=get_octopusvariable_quiet('Octopus.Deployment.Tenant.Name'))
    parser.add_argument('--template-repo-name',
                        action='store',
                        default=re.sub('[^a-zA-Z0-9]', '_', get_octopusvariable_quiet('Octopus.Project.Name').lower()))
    parser.add_argument('--repo-name',
                        action='store',
                        default=get_octopusvariable_quiet('Git.Url.RepoName') or get_octopusvariable_quiet(
                            'PreviewMerge.Git.Url.RepoName'))
    parser.add_argument('--generate-diff',
                        action='store_true',
                        default='false')
    parser.add_argument('--silent-fail',
                        action='store_true',
                        default='false')
    return parser.parse_known_args()


parser, _ = init_argparse()

exit_code = 0 if parser.silent_fail else 1
tenant_name_sanitized = re.sub('[^a-zA-Z0-9]', '_', parser.tenant_name.lower())
new_project_name_sanitized = re.sub('[^a-zA-Z0-9]', '_', parser.new_project_name.lower())
original_project_name_sanitized = re.sub('[^a-zA-Z0-9]', '_', parser.original_project_name.lower())
project_name_sanitized = new_project_name_sanitized if len(new_project_name_sanitized) != 0 \
    else original_project_name_sanitized
new_repo = parser.repo_name if len(parser.repo_name) != 0 else tenant_name_sanitized + '_' + project_name_sanitized
project_dir = '.octopus/project'
branch = 'main'

new_repo_url = parser.git_protocol + '://' + parser.git_host + '/' + parser.git_organization + '/' + new_repo + '.git'
new_repo_url_wth_creds = parser.git_protocol + '://' + parser.git_username + ':' + parser.git_password + '@' + \
                         parser.git_host + '/' + parser.git_organization + '/' + new_repo + '.git'
template_repo_name_url = parser.git_protocol + '://' + parser.git_host + '/' + parser.git_organization + '/' + \
                         parser.template_repo_name + '.git'
template_repo_name_url_with_creds = parser.git_protocol + '://' + parser.git_username + ':' + \
                                    parser.git_password + '@' + parser.git_host + '/' + \
                                    parser.git_organization + '/' + parser.template_repo_name + '.git'

if not check_repo_exists(new_repo_url, parser.git_username, parser.git_password):
    print('Downstream repo ' + new_repo_url + ' is not available')
    sys.exit(exit_code)

if not check_repo_exists(template_repo_name_url, parser.git_username, parser.git_password):
    print('Upstream repo ' + template_repo_name_url + ' is not available')
    sys.exit(exit_code)

# Set some default user details
execute(['git', 'config', '--global', 'user.email', 'octopus@octopus.com'])
execute(['git', 'config', '--global', 'user.name', 'Octopus Server'])

# Clone the template repo to test for a step template reference
os.mkdir('template')
execute(['git', 'clone', template_repo_name_url, 'template'])
if branch != 'master' and branch != 'main':
    execute(['git', 'checkout', '-b', branch, 'origin/' + branch], cwd='template')
else:
    execute(['git', 'checkout', branch], cwd='template')

try:
    with open('template/' + project_dir + '/deployment_process.ocl', 'r') as file:
        data = file.read()
        if 'ActionTemplates' in data:
            print('Template repo references a step template. ' +
                  'Step templates can not be merged across spaces or instances.')
            sys.exit(exit_code)
except Exception as ex:
    print(ex)
    print('Failed to open template/' + project_dir + '/deployment_process.ocl to check for ActionTemplates')

# Merge the template changes
repo_dir = 'repo'
os.mkdir(repo_dir)
execute(['git', 'clone', new_repo_url_wth_creds, repo_dir])
execute(['git', 'remote', 'add', 'upstream', template_repo_name_url_with_creds], cwd=repo_dir)
execute(['git', 'fetch', '--all'], cwd=repo_dir)
execute(['git', 'checkout', '-b', 'upstream-' + branch, 'upstream/' + branch], cwd=repo_dir)

# Checkout the project branch, assuming "main" or "master" are already linked upstream
if branch != 'master' and branch != 'main':
    execute(['git', 'checkout', '-b', branch, 'origin/' + branch], cwd=repo_dir)
else:
    execute(['git', 'checkout', branch], cwd=repo_dir)

git_diff_out, _, _ = execute(['git', 'diff', 'main...upstream-main'], cwd=repo_dir)

if len(git_diff_out) == 0:
    print('This project is up to date with the upstream repo at ' + template_repo_name_url)
    sys.exit(0)

if parser.generate_diff:
    with open('upstream.diff', 'w') as f:
        f.write(git_diff_out)

    execute(['diff2html', '-F', 'diff.html', '-i', 'file', '--', 'upstream.diff'])
    createartifact('diff.html', 'Git Diff')
    printhighlight(
        'Run the "Merge from Upstream" runbook to merge the changes shown in the diff into this project\'s repo')
else:
    print('The upstream repo has changes available to be merged into this project.')
