import ElCatalogueHeaderLinks from "../../components/el-catalogue-header-links";

// Phones: a second header row with Catalogue · Media · Membership.
// Hidden by CSS on wider screens, where the links sit beside the logo.
// Left out while a topic's title is docked in the header (reading a topic),
// so it doesn't take reading space there.
<template>
  {{#unless @outletArgs.minimized}}
    <div class="el-header-row">
      <ElCatalogueHeaderLinks @row={{true}} />
    </div>
  {{/unless}}
</template>
