// A little open book turning its pages, with a line saying what's happening.
// Used while the Library Manager / My loans pages wait on the library server.
// Pure CSS (see .el-reading in common.scss); people who prefer reduced motion
// see the book still.
<template>
  <div class="el-reading {{if @inline 'el-reading--inline'}}" role="status" aria-live="polite">
    <span class="el-reading__book" aria-hidden="true">
      <span class="el-reading__page"></span>
      <span class="el-reading__page"></span>
      <span class="el-reading__page"></span>
    </span>
    {{#if @label}}
      <span class="el-reading__label">{{@label}}</span>
    {{/if}}
  </div>
</template>
