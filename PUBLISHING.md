# Publishing to GitHub

The public repository is hosted at `tecxbro/FaceTime-picker`.

## Clone

```zsh
git clone https://github.com/tecxbro/FaceTime-picker.git
cd FaceTime-picker
```

## Publish from a local checkout

From the repository directory:

```zsh
gh auth status
git remote add origin git@github.com:tecxbro/FaceTime-picker.git
git push -u origin main
```

Before pushing changes, verify:

```zsh
zsh "./Validate Core Logic.command"
zsh ./build.sh
git status --short
```

Never commit runtime phone numbers, API URLs, authorization headers, local trusted-caller files, or environment files.
