# GitHub Workflow

This project currently tracks the upstream open-source repository on both GitHub and Gitee.

## Recommended remote layout

- `origin`: your own GitHub repository
- `upstream`: official GitHub upstream `https://github.com/joyapple/DD-CLASS.git`
- `gitee`: original Gitee mirror `https://gitee.com/joyapple2020/dd-class.git`

## 1. Create your own GitHub repository

Create an empty repository in your own GitHub account, for example:

- `https://github.com/<your-account>/dd-class-wailearning`

Do not initialize it with a README, `.gitignore`, or license.

## 2. Configure local remotes

Run this from PowerShell on your local machine:

```powershell
cd "C:\Users\haihu\Documents\New project\dd-class"
powershell -ExecutionPolicy Bypass -File .\scripts\setup_git_remotes.ps1 `
  -GitHubRepoUrl "https://github.com/<your-account>/dd-class-wailearning.git"
```

## 3. Push your current customized code

```powershell
cd "C:\Users\haihu\Documents\New project\dd-class"
git push -u origin main
git push origin --tags
```

## 4. Recommended daily workflow

```powershell
cd "C:\Users\haihu\Documents\New project\dd-class"
git checkout main
git pull --ff-only origin main
git checkout -b codex/<feature-name>
```

After your work is done:

```powershell
git add .
git commit -m "Describe the change"
git push -u origin codex/<feature-name>
```

Then merge the branch in GitHub, or fast-forward locally back into `main`.

## 5. Deploy from Git to the server

Once the server repository is connected to your GitHub repository, use:

```bash
cd /root/dd-class
bash scripts/pull_and_deploy.sh
```

This will:

1. Fetch the latest code from `origin`
2. Check out `main`
3. Pull the newest commit
4. Run the full deployment scripts

## 6. Sync with upstream open-source changes

```powershell
cd "C:\Users\haihu\Documents\New project\dd-class"
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

If upstream changes conflict with your customizations, resolve them locally before redeploying.
