import os
import subprocess

# 1. State: Everything is currently modified in the working tree.
# We will manipulate CHANGELOG.md and SkrivarApp.swift temporarily.

# Backup CHANGELOG.md
with open("CHANGELOG.md", "r") as f:
    changelog_orig = f.read()

# Create Onboarding-only CHANGELOG
changelog_onboarding = "\n".join([line for line in changelog_orig.split("\n") 
    if "Custom menu bar popover" not in line and "Docs updated" not in line])

with open("CHANGELOG.md", "w") as f:
    f.write(changelog_onboarding)

# Backup SkrivarApp.swift
with open("Sources/Skrivar/SkrivarApp.swift", "r") as f:
    skrivar_orig = f.read()

# Revert SkrivarApp.swift completely to HEAD, then we can apply only onboarding patch
subprocess.run(["git", "checkout", "HEAD", "--", "Sources/Skrivar/SkrivarApp.swift"])

# Apply only the onboarding changes to SkrivarApp.swift using a patch
# The onboarding changes are from line 1 to 135 roughly (the App struct body and init)
# We can just manually construct the file since we know exactly what changed,
# or we can just use `git add -p` programmatically, which is hard.
# Actually, the easiest way: SkrivarApp.swift onboarding changes just added `onboardingWindow`,
# `onboardingDone` logic, and `window` launching in `body`. 

