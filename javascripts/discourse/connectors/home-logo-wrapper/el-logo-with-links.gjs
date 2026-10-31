import ElCatalogueHeaderLinks from "../../components/el-catalogue-header-links";

// `home-logo-wrapper` is a wrapper outlet around the site logo: {{yield}}
// renders the logo as normal, and the library links follow straight after
// it, so they always sit beside the logo whatever else is in the header.
// On phones these are hidden by CSS and the second header row (after-header
// outlet) takes over.
<template>
  {{yield}}
  <ElCatalogueHeaderLinks />
</template>
