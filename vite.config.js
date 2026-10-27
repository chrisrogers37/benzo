import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { siteCopy } from './src/design/siteCopy.js'

const escapeAttribute = value => value.replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character])

export default defineConfig({
  plugins: [react(), {
    name: 'benzo-design-metadata',
    transformIndexHtml(html) {
      return html.replaceAll('%BENZO_TITLE%', escapeAttribute(siteCopy.metadata.title))
        .replaceAll('%BENZO_DESCRIPTION%', escapeAttribute(siteCopy.metadata.description))
        .replaceAll('%BENZO_CANONICAL%', escapeAttribute(siteCopy.metadata.canonical))
    },
  }],
  base: '/',
})
