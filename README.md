# cycle-gha-example
An example of how to use Cycle CLI within a GitHub Actions workflow.

# Dynamic Runners
The runners used for this workflow are dynamically spun up from an Azure scaleset. ▶️

- Using Azure CLI, we set the instance level to `1` to trigger a new instance of the respective scale sets (either our GitHub Actions scale set for `STABLE` testing, or the DevProg scaleset for `RC` testing) to be created.
- The Cycle features then run on the new scale set instance.
- After either `success` or `failure`, we use Azure CLI again to set the instance level back to `0` to deprovision our instance.

# Documentation
Please note this repo just serves as the repo for our GitHub Actions example, for **FULL DOCUMENTATION** on how to use `cycle-cli` with GitHub Actions please see our CI/CD example repository: [Using cycle-cli in a GitHub Actions pipeline](https://dev.azure.com/cyclelabs/cycle-codetemplates/_git/githubactions)
