import { Link } from 'react-router-dom'

import { getInsightsRecordPath } from './insightsPageSupport'
import type { InsightsTrajectory } from './insightsPageTypes'
import styles from './InsightsPage.module.css'

export default function InsightsSessionRoutes({
  trajectory,
}: {
  trajectory: InsightsTrajectory | null
}) {
  if (!trajectory?.routes?.length) return null
  return (
    <section
      className={`${styles.recordSection} ${styles.recordSectionWide}`}
      aria-label="Session routing history"
    >
      <div className={styles.recordSectionHeader}>
        <h2>Session routing history</h2>
        <span>
          {trajectory.recipe || 'Default recipe'} · {trajectory.routes.length} requests
        </span>
      </div>
      <div className={styles.projectionTraceWrap}>
        <table className={styles.projectionTraceTable}>
          <thead>
            <tr>
              {['Turn', 'Decision', 'Model', 'Action', 'Reason', 'Result', 'Duration'].map(
                (heading) => (
                  <th key={heading}>{heading}</th>
                ),
              )}
            </tr>
          </thead>
          <tbody>
            {trajectory.routes.map((route) => (
              <tr key={route.record_id}>
                <td>
                  <Link to={getInsightsRecordPath(route.record_id)}>{route.turn_index + 1}</Link>
                </td>
                <td>{route.decision || 'Unresolved'}</td>
                <td>
                  {route.previous_model ? `${route.previous_model} → ` : ''}
                  {route.selected_model || 'No backend selected'}
                </td>
                <td>
                  {route.session_action || 'Not recorded'}
                  {route.session_policy_applied ? ' · protection applied' : ''}
                </td>
                <td>{route.session_reason || route.selection_reasoning || 'Not recorded'}</td>
                <td>
                  {route.lifecycle_state}
                  {route.response_status ? ` · HTTP ${route.response_status}` : ''}
                </td>
                <td>
                  {route.lifecycle_state === 'in_progress'
                    ? 'In progress'
                    : `${route.duration_ms} ms`}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}
