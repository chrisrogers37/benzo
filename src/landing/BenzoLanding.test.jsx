// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import App from '../App'
import { siteCopy } from '../design/siteCopy'

afterEach(cleanup)
const click = name => fireEvent.click(screen.getByRole('button', { name, exact: true }))
const switchMaster = () => fireEvent.click(screen.getByRole('switch', { name: /^(Apply selected settings|Restore captured settings)$/ }))
function completeSetup() {
  click('Power Access')
  click('Set Up Power Access')
  click('Done')
}

function expectPageState(active) {
  const root = document.querySelector('.benzo-site')
  expect(root.dataset.benzoActive).toBe(String(active))
  expect(root.style.getPropertyValue('--glow-opacity')).toBe(active ? '1' : '0')
  expect(root.style.getPropertyValue('--rose')).toBe(active ? '#9b3e65' : '#262923')
  expect(root.style.getPropertyValue('--brand-surface')).toBe(active ? '#f0d5e0' : '#e9e9e2')
  expect(root.style.getPropertyValue('--final-surface')).toBe(active ? '#efdbe3' : '#e9e9e2')
}

describe('shared page and app state', () => {
  it('connects phase transitions to the whole page and preserves available target choices', () => {
    render(<App />)
    expectPageState(true)
    switchMaster()
    expectPageState(false)
    expect(screen.getByRole('switch', { name: /^(Apply selected settings|Restore captured settings)$/ }).getAttribute('aria-checked')).toBe('false')
    expect(screen.getByRole('checkbox', { name: 'Hibernate Mode' }).disabled).toBe(true)
    click('First launch'); completeSetup(); click('Options')
    expect(screen.getByRole('checkbox', { name: 'Disable TCP Keep-Alive' }).disabled).toBe(false)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Disable TCP Keep-Alive' }))
    expectPageState(false)
    switchMaster()
    expectPageState(true)
    expect(screen.getByRole('checkbox', { name: 'Disable TCP Keep-Alive' }).getAttribute('aria-checked')).toBe('true')
  })

  it('keeps restore, first launch, sleep, quit, and restart synchronized with the page', () => {
    render(<App />)
    click('System Defaults'); expectPageState(false)
    expect(screen.getByRole('button', { name: 'Sleep Now' }).disabled).toBe(true)
    click('Sleep Now'); expectPageState(false)
    click('First launch'); expectPageState(false)
    expect(screen.getByRole('switch', { name: /^(Apply selected settings|Restore captured settings)$/ }).disabled).toBe(true)
    completeSetup(); expectPageState(false)
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

  it('distinguishes the unreleased demo changes from existing downloads', () => {
    render(<App />)
    expect(screen.getByText('Downloads are existing releases; the demo previews unreleased changes.')).toBeTruthy()
    expect(screen.getByText(/containment changes shown here are unreleased/)).toBeTruthy()
    click('About this demo')
    expect(screen.getByText(/controls follow unreleased source changes, not the downloadable app/)).toBeTruthy()
    expect(screen.queryByText('Check sleep blockers')).toBeNull()
    expect(screen.queryByText(/or set a timer/)).toBeNull()
  })
})
