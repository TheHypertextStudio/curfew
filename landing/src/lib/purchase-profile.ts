import deployment from '../../../deployment/generated/environments.mjs';

type PurchaseProfile = { issuer: string; scheme: 'curfew' | 'curfew-dev' };
type LicenseOrigins = Readonly<Record<'production' | 'staging', { licenseOrigin: string }>>;

export function purchaseProfile(
  mode: string,
  profiles: LicenseOrigins = deployment,
): PurchaseProfile {
  if (mode !== 'production' && mode !== 'staging' && mode !== 'local') {
    throw new Error('Unknown purchase deployment mode');
  }
  return {
    issuer: profiles[mode === 'local' ? 'staging' : mode].licenseOrigin,
    scheme: mode === 'production' ? 'curfew' : 'curfew-dev',
  };
}
