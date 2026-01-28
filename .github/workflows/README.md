# Canvas Assignment Sync Workflow

This GitHub Actions workflow automatically syncs changed ACTIVITY, LAB, HOMEWORK, and TOOL markdown files to Canvas when you push to the `main` branch.

## How It Works

1. **Triggers**: Runs automatically on push to `main` branch when `.md` files are changed
2. **Detection**: Identifies changed files matching patterns:
   - `ACTIVITY_*.md`
   - `LAB_*.md`
   - `HOMEWORK*.md`
   - `TOOL*.md`
3. **Filtering**: Only syncs files that have a `github_path` mapping in `canvastest/assignments_metadata_5381.json` (from private canvastest repository)
4. **Syncing**: Updates Canvas assignment descriptions using the `canvastest` submodule

## Setup

### 1. Required GitHub Secrets

You must configure the following secrets in your GitHub repository settings:

1. **`CANVAS_API_KEY`**
   - Your Canvas API authentication token
   - Get it from: Canvas → Account → Settings → New Access Token
   - **Important**: Never commit this key to the repository

2. **`CANVAS_COURSE_ID`**
   - Your Canvas course ID (integer)
   - Found in the Canvas course URL: `https://canvas.cornell.edu/courses/COURSE_ID`
   - Example: If URL is `https://canvas.cornell.edu/courses/81764`, the ID is `81764`

3. **`SUBMODULE_SSH_KEY`** (Required if canvastest is private)
   - SSH private key for accessing the private `canvastest` submodule
   - See "Setting Up SSH Access for Private Submodule" below for detailed instructions

#### How to Add Secrets

1. Go to your repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret with the exact names above

### 1a. Setting Up SSH Access for Private Submodule

If your `canvastest` repository is private, you need to set up SSH authentication so the workflow can access it.

#### Step 1: Generate SSH Key Pair

On your local machine, generate a new SSH key (if you don't already have one for this purpose):

```bash
ssh-keygen -t ed25519 -C "github-actions-canvastest" -f ~/.ssh/github_actions_canvastest
```

**Important**: Do NOT use a passphrase (press Enter when prompted).

This creates two files:
- `~/.ssh/github_actions_canvastest` (private key) - **Keep this secret!**
- `~/.ssh/github_actions_canvastest.pub` (public key) - You'll add this to GitHub

#### Step 2: Add Public Key as Deploy Key   

1. Go to your **private** `canvastest` repository on GitHub
2. Click **Settings** → **Deploy keys** → **Add deploy key**
3. **Title**: `GitHub Actions - dsai sync`
4. **Key**: Paste the contents of `~/.ssh/github_actions_canvastest.pub`
5. ✅ Check **Allow write access** (if you need to update the repo, otherwise read-only is fine)
6. Click **Add key**

#### Step 3: Add Private Key as Secret

1. Go to your **public** `dsai` repository on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions** → **New repository secret**
3. **Name**: `SUBMODULE_SSH_KEY`
4. **Secret**: Paste the **entire contents** of `~/.ssh/github_actions_canvastest` (the private key)
   - Include the `-----BEGIN OPENSSH PRIVATE KEY-----` header
   - Include the `-----END OPENSSH PRIVATE KEY-----` footer
   - Include all lines in between
5. Click **Add secret**

#### Step 4: Verify Setup

After pushing to `main`, check the workflow logs:
- Look for "Setup SSH for private submodule" step
- Should see "Checkout submodules" step completing successfully
- If you see authentication errors, verify the SSH key was copied correctly

**Security Notes**:
- The private key is stored securely as a GitHub secret
- Deploy keys are repository-specific and more secure than PATs
- The workflow automatically configures SSH before checking out submodules

### 2. Submodule Setup

The workflow requires the `canvastest` submodule to be initialized:

```bash
git submodule update --init --recursive
```

### 3. Assignments Metadata File

The workflow uses `canvastest/assignments_metadata_5381.json` from the **private** `canvastest` repository. This file must exist with `github_path` mappings for each assignment you want to sync.

#### Why Private?

The metadata file contains assignment IDs, names, and mappings that you may prefer to keep private. By storing it in the private `canvastest` repository, it's not exposed in the public `dsai` repository.

#### Creating/Updating the Metadata File

1. In your local `canvastest` repository, run the fetch script (see [canvastest README](../../canvastest/README.md))
2. Save the metadata as `assignments_metadata_5381.json` (or copy and rename from `assignments_metadata.json`)
3. Edit the file to add `github_path` entries for each assignment
4. Commit and push to the **private** `canvastest` repository

Example entry:

```json
{
  "id": 123456,
  "name": "Install Git and Git Bash",
  "points_possible": 10,
  "github_path": "00_quickstart/ACTIVITY_git.md"
}
```

**Important**: 
- Only files with `github_path` entries will be synced
- Files without mappings will be skipped
- The file must be named `assignments_metadata_5381.json` in the `canvastest` repository root

## Workflow Behavior

### What Gets Synced

- Only files that:
  1. Match the assignment patterns (ACTIVITY_, LAB_, HOMEWORK*, TOOL*)
  2. Were changed in the push
  3. Have a `github_path` mapping in `assignments_metadata.json`

### What Gets Skipped

- Files that don't match assignment patterns
- Files without `github_path` mappings
- Non-markdown files

### Error Handling

- If a single file fails to sync, the workflow logs the error and continues with other files
- The workflow fails only if critical setup fails (R installation, submodule checkout)
- Check workflow logs for detailed error messages

## Workflow Logs

After pushing to `main`, you can view workflow runs:

1. Go to your repository on GitHub
2. Click **Actions** tab
3. Select the **Canvas Assignment Sync** workflow
4. Click on a run to see detailed logs

## Troubleshooting

### Workflow doesn't run

- **Check**: Did you push to `main` branch?
- **Check**: Did you change any `.md` files?
- **Check**: Is the workflow file in `.github/workflows/canvas-sync.yml`?

### "No changed assignment files found"

- This is normal if you didn't change any ACTIVITY/LAB/HOMEWORK/TOOL files
- The workflow will skip syncing

### "assignments_metadata_5381.json not found"

- **Cause**: The file doesn't exist in the private `canvastest` repository, or SSH authentication failed
- **Solution**: 
  1. Verify `assignments_metadata_5381.json` exists in the `canvastest` repository root
  2. Check that `SUBMODULE_SSH_KEY` secret is configured correctly
  3. Verify the deploy key was added to the `canvastest` repository
  4. Check workflow logs for SSH authentication errors

### "No assignment found with github_path"

- **Cause**: The changed file doesn't have a `github_path` entry in `assignments_metadata.json`
- **Solution**: Add the `github_path` mapping for that file in the metadata file
- The workflow will skip files without mappings (this is expected behavior)

### "CANVAS_API_KEY not found"

- **Cause**: Secret not configured or incorrectly named
- **Solution**: Verify the secret is named exactly `CANVAS_API_KEY` in repository settings

### "Failed to sync" errors

- Check the workflow logs for specific error messages
- Common causes:
  - Invalid Canvas API key
  - Network issues
  - Canvas API rate limits (workflow will retry automatically)
  - Invalid markdown content

### Submodule issues

- **Error**: "Cannot find canvastest/R directory"
- **Solution**: Ensure submodule is initialized:
  ```bash
  git submodule update --init --recursive
  ```

## Security Notes

Since this is a **public repository**:

- ✅ **Secrets are secure**: GitHub Actions secrets are never exposed in logs or code
- ✅ **Workflow is visible**: Anyone can see the workflow file (this is fine - no secrets in it)
- ✅ **Private metadata**: `assignments_metadata_5381.json` stays in private `canvastest` repo
- ✅ **SSH keys**: Private SSH key is stored securely as a secret, never exposed
- ⚠️ **Be careful**: Never log or echo secrets in workflow steps
- ⚠️ **Check logs**: Ensure R scripts don't accidentally print API keys
- ⚠️ **SSH key security**: The SSH private key should only be used as a deploy key for `canvastest`

The workflow automatically masks secrets in logs. The `.env` file created during workflow execution is temporary and never committed.

**Why keep metadata private?**
- Assignment IDs and Canvas course structure details
- Internal mapping information
- While not highly sensitive, keeping it private provides an extra layer of security

## Cost

**Free!** Since this is a public repository, GitHub Actions provides unlimited free minutes. You can run this workflow as frequently as needed without any cost concerns.

## Manual Testing

To test the sync script locally:

```bash
# Create a test file with changed files
echo "00_quickstart/ACTIVITY_git.md" > test_changed.txt

# Run the sync script (from repository root)
Rscript canvastest/scripts/sync_changed_files.R \
  test_changed.txt \
  course_config.json \
  canvastest/assignments_metadata_5381.json
```

**Note**: The sync script and SSH setup scripts are located in the private `canvastest` repository at `canvastest/scripts/` to keep sensitive setup information secure.

## Related Documentation

- [canvastest Module README](../canvastest/README.md) - Detailed documentation of the sync module
- [canvastest Workflow Documentation](../canvastest/docs/WORKFLOW.md) - Step-by-step workflow procedures
- [canvastest Configuration Guide](../canvastest/docs/CONFIGURATION.md) - Configuration options

## Scripts Location

All scripts (including `sync_changed_files.R` and SSH setup scripts) are located in the **private** `canvastest` repository at `canvastest/scripts/`. This ensures sensitive setup information and scripts are not exposed in the public `dsai` repository.

## Support

If you encounter issues:

1. Check the workflow logs in the **Actions** tab
2. Review the troubleshooting section above
3. Consult the canvastest documentation
4. Verify all secrets are configured correctly
