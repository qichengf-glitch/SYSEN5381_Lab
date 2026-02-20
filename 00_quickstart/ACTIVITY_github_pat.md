# 📌 ACTIVITY

## Getting Your Github Personal Access Token 

for Commit, Pull, and Push Operations with Github Repositories

*Estimated Time: 10 minutes*

---

## ✅ Your Task

In this activity, you are asked to follow the necessary steps to allow you to commit, pull, and push changes on GitHub repositories. Please be sure to create a GitHub Repository first.

## Prerequisites 
- [ ] Must have already made a GitHub Account
- [ ] Must have already made or been added to a GitHub Repository 
- [ ] Must have the complete URL of the GitHub Repository. For example, our GitHub Repository is https://GitHub.com/timothyfraser/dsai.git


## Checklist

*Note: you can check these boxes off as you go!*

### Get your Personal Access Token

- [ ] Navigate to **GitHub.com** and click on your profile icon in the upper right hand corner. 
- [ ] Click on **Profile**
- [ ] In the left hand menu, navigate to **Developer Settings**
- [ ] Select **Create a Personal Access Token**. You can either make a fine-grained token, where you specify the repository that this token will grant you access to, or a classic token, which will grant the bearer access to all your GitHub repositories. 
    - If **Classic Token**:
      - [ ] Create a name for the token 
      - [ ] Create an expiration date for the token. Pick one after the end of this term.
      - [ ] Under scopes, you are asked to select what powers to give to this token - EG what functions do you allow a user who bears your token to perform? Please select the public_repo scope and repo scope.
    - If **Fine-Grained Token**:
      - [ ] Create a name for the token 
      - [ ] Create an expiration date for the token. Pick one after the end of this term.
      - [ ] Under Permissions, select **Contents**, which will automatically also add the **Metadata** permissions. Make sure Contents is set to **Read and Write**.
- [ ] Copy the token, and store it in a secure location. Some people put them in their password manager app; others put them in a note-taking app.

![Setting a Fine-Grained Token](../images/github_pat.png)

### Use your Personal Access Token

- [ ] Create a new project from GitHub, using your repositories GitHub URL. Should end in .git
- [ ] Open up your coding environment - eg. Posit Cloud / RStudio / Positron / Cursor / VSCode
- [ ] Install these 3 packages: `install.packages(c("usethis", "gert", "credentials"))`
- [ ] Create one new `.R` script file.
- [ ] Run the following script below, and then look at the output of your R console and terminal.

```r
# If you haven't yet, install these two packages:
install.packages(c("gert", "credentials"))
# Load packages
library(usethis) # for coding management helper functions
library(gert) # for github operations like commit, pull, and push
library(credentials) # for authenticating with github

# You might want to put your Personal Access Token in a .env file
# Create a .env 'environmental variables' file
file.create(".env")
# open the file and add: GITHUB_PAT=whatever_it_was_here

# and then add the .env file to the .gitignore file,
# which lists which files should NEVER be uploaded to a github repository for security reasons.
usethis::use_git_ignore(".env")
# Also 'vaccinate' your computer's global .gitignore file - which helps keep sensitive files out. 
# Won't change your repository's .gitignore
usethis::git_vaccinate()


# Set your Github Personal Access Token
credentials::set_github_pat()
# this will prompt a popup that asks you to enter your GitHub Personal Access Token.


# pull most recent changes from GitHub
gert::git_pull() 

# select any and all new files created or edited to be 'staged'
# 'staged' files are to be saved anew on GitHub 
# dir(all.files = TRUE) selects ALL files to be added.
gert::git_add(dir(all.files = TRUE)) 

# save your record of file edits - called a commit
gert::git_commit_all("my first commit") 

# push your commit to GitHub
gert::git_push() 
```



## 📤 To Submit

- For credit: Just confirm that you've finished this step in the CANVAS textbox.

---

![](../docs/images/icons.png)

---

← 🏠 [Back to Top](#ACTIVITY)
