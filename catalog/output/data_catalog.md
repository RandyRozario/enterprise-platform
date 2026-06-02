# Enterprise Data Catalog — multitenant_db

> Generated: 2026-06-02T01:13:04.945033+00:00  
> Extraction time: 457.8ms  
> Quality score: 81.4/100

## Database Summary

| Property | Value |
|---|---|
| Database | multitenant_db |
| Version | PostgreSQL 16.14 on x86_64-pc-linux-musl, compiled by gcc (A |
| Total tables | 7 |
| Total rows | -7 |
| Total size | 392.0 KB |
| RLS-enabled tables | 5 |
| Tenant-isolated tables | 5 |

## Table Reference

### `public._prisma_migrations` ⚠️ No RLS 

**Rows:** -1  |  **Size:** 32.0 KB  |  **Indexes:** 1

| Column | Type | Nullable | PK | FK | References |
|---|---|---|---|---|---|
| `id` | `character varying` | NO | ✓ |  |  |
| `checksum` | `character varying` | NO |  |  |  |
| `finished_at` | `timestamp with time zone` | YES |  |  |  |
| `migration_name` | `character varying` | NO |  |  |  |
| `logs` | `text` | YES |  |  |  |
| `rolled_back_at` | `timestamp with time zone` | YES |  |  |  |
| `started_at` | `timestamp with time zone` | NO |  |  |  |
| `applied_steps_count` | `integer` | NO |  |  |  |

---

### `public.audit_logs` 🔒 RLS 🏢 MT

**Rows:** -1  |  **Size:** 32.0 KB  |  **Indexes:** 3

**RLS Policies:**

- `audit_logs_tenant_isolation_insert`
- `audit_logs_tenant_isolation_select`

| Column | Type | Nullable | PK | FK | References |
|---|---|---|---|---|---|
| `id` | `uuid` | NO | ✓ |  |  |
| `tenantId` | `uuid` | NO |  | ✓ | `tenants.id` |
| `action` | `text` | NO |  |  |  |
| `entityType` | `text` | NO |  |  |  |
| `entityId` | `text` | YES |  |  |  |
| `actorId` | `text` | YES |  |  |  |
| `ipAddress` | `text` | YES |  |  |  |
| `userAgent` | `text` | YES |  |  |  |
| `metadata` | `jsonb` | YES |  |  |  |
| `createdAt` | `timestamp without time zone` | NO |  |  |  |

---

### `public.order_items` 🔒 RLS 🏢 MT

**Rows:** -1  |  **Size:** 56.0 KB  |  **Indexes:** 3

**RLS Policies:**

- `order_items_tenant_isolation_delete`
- `order_items_tenant_isolation_insert`
- `order_items_tenant_isolation_select`
- `order_items_tenant_isolation_update`

| Column | Type | Nullable | PK | FK | References |
|---|---|---|---|---|---|
| `id` | `uuid` | NO | ✓ |  |  |
| `tenantId` | `uuid` | NO |  |  |  |
| `orderId` | `uuid` | NO |  | ✓ | `orders.id` |
| `productId` | `uuid` | NO |  | ✓ | `products.id` |
| `quantity` | `integer` | NO |  |  |  |
| `unitPrice` | `numeric` | NO |  |  |  |
| `totalPrice` | `numeric` | NO |  |  |  |

---

### `public.orders` 🔒 RLS 🏢 MT

**Rows:** -1  |  **Size:** 64.0 KB  |  **Indexes:** 3

**RLS Policies:**

- `orders_tenant_isolation_delete`
- `orders_tenant_isolation_insert`
- `orders_tenant_isolation_select`
- `orders_tenant_isolation_update`

| Column | Type | Nullable | PK | FK | References |
|---|---|---|---|---|---|
| `id` | `uuid` | NO | ✓ |  |  |
| `tenantId` | `uuid` | NO |  | ✓ | `tenants.id` |
| `userId` | `uuid` | NO |  | ✓ | `users.id` |
| `status` | `USER-DEFINED` | NO |  |  |  |
| `totalAmount` | `numeric` | NO |  |  |  |
| `notes` | `text` | YES |  |  |  |
| `createdAt` | `timestamp without time zone` | NO |  |  |  |
| `updatedAt` | `timestamp without time zone` | NO |  |  |  |

---

### `public.products` 🔒 RLS 🏢 MT

**Rows:** -1  |  **Size:** 64.0 KB  |  **Indexes:** 3

**RLS Policies:**

- `products_tenant_isolation_delete`
- `products_tenant_isolation_insert`
- `products_tenant_isolation_select`
- `products_tenant_isolation_update`

| Column | Type | Nullable | PK | FK | References |
|---|---|---|---|---|---|
| `id` | `uuid` | NO | ✓ |  |  |
| `tenantId` | `uuid` | NO |  | ✓ | `tenants.id` |
| `name` | `text` | NO |  |  |  |
| `description` | `text` | YES |  |  |  |
| `price` | `numeric` | NO |  |  |  |
| `sku` | `text` | NO |  |  |  |
| `stock` | `integer` | NO |  |  |  |
| `isActive` | `boolean` | NO |  |  |  |
| `createdAt` | `timestamp without time zone` | NO |  |  |  |
| `updatedAt` | `timestamp without time zone` | NO |  |  |  |

---

### `public.tenants` ⚠️ No RLS 

**Rows:** -1  |  **Size:** 80.0 KB  |  **Indexes:** 4

| Column | Type | Nullable | PK | FK | References |
|---|---|---|---|---|---|
| `id` | `uuid` | NO | ✓ |  |  |
| `name` | `text` | NO |  |  |  |
| `slug` | `text` | NO |  |  |  |
| `plan` | `USER-DEFINED` | NO |  |  |  |
| `isActive` | `boolean` | NO |  |  |  |
| `apiKey` | `uuid` | NO |  |  |  |
| `createdAt` | `timestamp without time zone` | NO |  |  |  |
| `updatedAt` | `timestamp without time zone` | NO |  |  |  |

---

### `public.users` 🔒 RLS 🏢 MT

**Rows:** -1  |  **Size:** 64.0 KB  |  **Indexes:** 3

**RLS Policies:**

- `users_tenant_isolation_delete`
- `users_tenant_isolation_insert`
- `users_tenant_isolation_select`
- `users_tenant_isolation_update`

| Column | Type | Nullable | PK | FK | References |
|---|---|---|---|---|---|
| `id` | `uuid` | NO | ✓ |  |  |
| `tenantId` | `uuid` | NO |  | ✓ | `tenants.id` |
| `email` | `text` | NO |  |  |  |
| `name` | `text` | NO |  |  |  |
| `role` | `USER-DEFINED` | NO |  |  |  |
| `passwordHash` | `text` | NO |  |  |  |
| `isActive` | `boolean` | NO |  |  |  |
| `createdAt` | `timestamp without time zone` | NO |  |  |  |
| `updatedAt` | `timestamp without time zone` | NO |  |  |  |

---
