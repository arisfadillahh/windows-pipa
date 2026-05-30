# Publish to GitHub

The local repository is already committed. To publish it:

1. Create an empty GitHub repository, for example `pipa-woa`.
2. Do not add a README, license, or gitignore on GitHub because this repo
   already has them.
3. Run:

```powershell
.\scripts\Publish-GitHub.ps1 -RepositoryUrl "https://github.com/YOUR_USER/pipa-woa.git"
```

If SSH is configured:

```powershell
.\scripts\Publish-GitHub.ps1 -RepositoryUrl "git@github.com:YOUR_USER/pipa-woa.git"
```

## Connector path

If Codex has access to an existing GitHub repo through the GitHub connector,
provide the repo name in `owner/name` format. The files can then be uploaded
there directly.

