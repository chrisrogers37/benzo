// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import App from '../App'
import { siteCopy } from '../design/siteCopy'

afterEach(cleanup)
const click = name => fireEvent.click(screen.getByRole('button', { name, exact: true }))
const switchMaster = () => fireEvent.click(screen.getByRole('switch', { name: 'Deep Sleep' }))

function expectPageState(active) {
  const root = document.querySelector('.benzo-site')
  expect(root.dataset.benzoActive).toBe(String(active))
  expect(root.style.getPropertyValue('--glow-opacity')).toBe(active ? '1' : '0')
  expect(root.style.getPropertyValue('--rose')).toBe(active ? '#9b3e65' : '#262923')
  expect(root.style.getPropertyValue('--brand-surface')).toBe(active ? '#f0d5e0' : '#e9e9e2')
  expect(root.style.getPropertyValue('--final-surface')).toBe(active ? '#efdbe3' : '#e9e9e2')
}

describe('shared page and app state', () => {
  it('connects the actual master switch to the whole page and preserves control preferences', () => {
    render(<App />)
    expectPageState(true)
    switchMaster()
    expectPageState(false)
    expect(screen.getByRole('switch', { name: 'Deep Sleep' }).getAttribute('aria-checked')).toBe('false')
    fireEvent.click(screen.getByRole('checkbox', { name: 'Hibernate Mode' }))
    expectPageState(false)
    switchMaster()
    expectPageState(true)
    expect(screen.getByRole('checkbox', { name: 'Hibernate Mode' }).getAttribute('aria-checked')).toBe('false')
  })

  it('keeps restore, first launch, sleep, quit, and restart synchronized with the page', () => {
    render(<App />)
    click('Restore System Defaults'); expectPageState(false)
    click('Sleep Now'); expectPageState(true)
    click('First launch'); expectPageState(false)
    click('Grant Permission'); expectPageState(false)
    switchMaster(); expectPageState(true)
    click('Quit'); expectPageState(false)
    // The toolbar and closed panel each offer a restart.
    fireEvent.click(screen.getAllByRole('button', { name: /Restart demo/ })[0])
    expectPageState(true)
  })

  it('uses the approved public page without draft chrome or a noindex override', () => {
    render(<App />)
    for (const link of screen.getAllByRole('link', { name: /Get Benzo/ })) {
      expect(link.getAttribute('href')).toBe(siteCopy.links.releases)
    }
    expect(screen.getByText('Built because I wanted my Mac to sleep when I do.')).toBeTruthy()
    expect(screen.getByRole('link', { name: 'Contact' }).getAttribute('href')).toBe('mailto:contact@benzo.work')
    expect(screen.queryByText('Draft 02 · Design preview')).toBeNull()
    expect(screen.queryByRole('link', { name: /Compare original/ })).toBeNull()
    expect(document.querySelector('meta[name="robots"]')).toBeNull()
  })
})
