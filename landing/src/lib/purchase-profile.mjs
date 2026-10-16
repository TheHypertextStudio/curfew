import deployment from '../../../deployment/generated/environments.mjs';

export function purchaseProfile(mode, profiles = deployment) {
  if (mode !== 'production' && mode !== 'staging' && mode !== 'local') {
    throw new Error('Unknown purchase deployment mode');
  }
  const schemes = { production: 'curfew', staging: 'curfew-studio-dev', local: 'curfew-dev' };
  return { issuer: profiles[mode].licenseOrigin, scheme: schemes[mode] };
}
