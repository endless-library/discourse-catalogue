import ElCatalogueHeaderLinks from "../../components/el-catalogue-header-links";

// Phones: a second header row with Catalogue · Media · Membership.
// Hidden by CSS on wider screens, where the links sit beside the logo.
//
// Always shown, including while a topic's title is docked in the header.
// (It used to hide then, but that changed the header's height, which moved
// the page, which undocked the title, which brought the row back… and the
// header flickered between the two states.)
<template>
  <div class="el-header-row">
    <ElCatalogueHeaderLinks @row={{true}} />
  </div>
</template>
