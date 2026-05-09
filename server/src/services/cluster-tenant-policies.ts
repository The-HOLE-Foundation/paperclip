import { and, eq } from "drizzle-orm";
import type { Db } from "@paperclipai/db";
import { clusterTenantPolicies } from "@paperclipai/db";
import type { TenantPolicy } from "@paperclipai/execution-target-kubernetes";

export interface UpsertTenantPolicyInput {
  clusterConnectionId: string;
  companyId: string;
  quota: TenantPolicy["quota"];
  limitRange: TenantPolicy["limitRange"];
  additionalAllowFqdns: string[];
  /**
   * Egress HTTP proxy URL for the tenant. When omitted (undefined), any existing
   * value is preserved on upsert; pass `null` explicitly to clear it.
   */
  httpProxyUrl?: string | null;
  imageOverrides: Record<string, string> | null;
}

export interface TenantPolicyRow extends TenantPolicy {
  clusterConnectionId: string;
  companyId: string;
  httpProxyUrl: string | null;
}

export interface ClusterTenantPoliciesService {
  get(clusterConnectionId: string, companyId: string): Promise<TenantPolicyRow | null>;
  upsert(input: UpsertTenantPolicyInput): Promise<TenantPolicyRow>;
}

export function clusterTenantPoliciesService(db: Db): ClusterTenantPoliciesService {
  return {
    async get(clusterConnectionId, companyId) {
      const [row] = await db.select().from(clusterTenantPolicies).where(and(
        eq(clusterTenantPolicies.clusterConnectionId, clusterConnectionId),
        eq(clusterTenantPolicies.companyId, companyId),
      ));
      return row ? mapRow(row) : null;
    },

    async upsert(input) {
      const existing = await this.get(input.clusterConnectionId, input.companyId);
      // Preserve httpProxyUrl when the caller didn't explicitly pass one (undefined).
      // An explicit `null` clears it; an explicit string overwrites it.
      const httpProxyUrl =
        input.httpProxyUrl === undefined ? (existing?.httpProxyUrl ?? null) : input.httpProxyUrl;

      if (existing) {
        const [updated] = await db.update(clusterTenantPolicies).set({
          quotaJson: input.quota,
          limitRangeJson: input.limitRange,
          networkJson: { additionalAllowFqdns: input.additionalAllowFqdns, httpProxyUrl },
          imageOverridesJson: input.imageOverrides,
          updatedAt: new Date(),
        }).where(and(
          eq(clusterTenantPolicies.clusterConnectionId, input.clusterConnectionId),
          eq(clusterTenantPolicies.companyId, input.companyId),
        )).returning();
        return mapRow(updated);
      }
      const [created] = await db.insert(clusterTenantPolicies).values({
        clusterConnectionId: input.clusterConnectionId,
        companyId: input.companyId,
        quotaJson: input.quota,
        limitRangeJson: input.limitRange,
        networkJson: { additionalAllowFqdns: input.additionalAllowFqdns, httpProxyUrl },
        imageOverridesJson: input.imageOverrides,
      }).returning();
      return mapRow(created);
    },
  };
}

function mapRow(r: typeof clusterTenantPolicies.$inferSelect): TenantPolicyRow {
  return {
    clusterConnectionId: r.clusterConnectionId,
    companyId: r.companyId,
    quota: r.quotaJson ?? null,
    limitRange: r.limitRangeJson ?? null,
    additionalAllowFqdns: r.networkJson?.additionalAllowFqdns ?? [],
    httpProxyUrl: r.networkJson?.httpProxyUrl ?? null,
    imageOverrides: r.imageOverridesJson ?? null,
  };
}
