# sslchef
Auto renew ssl cert for sql server using chef recipe
We will be running a powershell script that will be uploaded to chef server as a recipe.

For this recipe we need to store credentials used by the powershell in a gcp bucket, like shown below.
{
  "sb": "put cert password for sb here",
  "prd": "put cert password for prd here",
  "sb_user": "sb_user_name",
  "sb_pass": "put password for sb_user here",
  "prd_user": "prd_user_password"
  "prd_pass": "put password for prd user here"
}
