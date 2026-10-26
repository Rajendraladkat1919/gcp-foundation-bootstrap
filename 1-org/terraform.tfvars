# REPLACE_ME values below before the first apply. Nothing here is secret.
prefix                = "pe"
organization_id       = "organizations/351904638555"
directory_customer_id = "C02jnng98"
domain                = "platform-engineering.site"
region                = "us-west2"

groups = {
  platform_engineers = "arp-platform-engineers@platform-engineering.site"
  developers         = "grp-developer@platform-engineering.site"
}

business_units = {
  business-unit-0 = {
    display_name = "Business Unit 0"
    group        = "business-unit-commercial@platform-engineering.site"
  }
}
