package com.octopus.wallet;

import android.content.Intent;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.appcompat.widget.PopupMenu;
import androidx.recyclerview.widget.RecyclerView;
import java.util.ArrayList;
import java.util.List;

/**
 * Startpage recent-visits list: favicon with letter-avatar fallback, title, domain, and a menu
 * (open / new tab / delete).
 */
public final class RecentVisitsAdapter extends RecyclerView.Adapter<RecentVisitsAdapter.VH> {

  /** Open target for a visit tap. */
  public interface Listener {
    void onOpen(RecentVisitsStore.Entry entry);

    void onOpenNewTab(RecentVisitsStore.Entry entry);

    void onDelete(RecentVisitsStore.Entry entry);
  }

  private final List<RecentVisitsStore.Entry> items = new ArrayList<>();
  private final Listener listener;

  public RecentVisitsAdapter(Listener listener) {
    this.listener = listener;
  }

  public void submit(List<RecentVisitsStore.Entry> entries) {
    items.clear();
    if (entries != null) items.addAll(entries);
    notifyDataSetChanged();
  }

  @NonNull
  @Override
  public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
    View v =
        LayoutInflater.from(parent.getContext()).inflate(R.layout.item_recent_visit, parent, false);
    return new VH(v);
  }

  @Override
  public void onBindViewHolder(@NonNull VH holder, int position) {
    RecentVisitsStore.Entry e = items.get(position);
    String title = e.title == null || e.title.trim().isEmpty() ? e.domain : e.title;
    holder.title.setText(title);
    holder.domain.setText(e.domain == null || e.domain.isEmpty() ? e.url : e.domain);
    String avatar = "?";
    if (e.domain != null && !e.domain.trim().isEmpty()) {
      avatar = e.domain.trim().substring(0, 1).toUpperCase(java.util.Locale.US);
    } else if (title != null && !title.trim().isEmpty()) {
      avatar = title.trim().substring(0, 1).toUpperCase(java.util.Locale.US);
    }
    holder.avatar.setText(avatar);
    bindFavicon(holder, e);
    holder.itemView.setOnClickListener(
        v -> {
          if (listener != null) listener.onOpen(e);
        });
    holder.menu.setOnClickListener(
        v -> {
          PopupMenu popup = new PopupMenu(v.getContext(), holder.menu);
          popup.getMenu().add(0, 1, 0, "Open");
          popup.getMenu().add(0, 2, 0, "Open in new tab");
          popup.getMenu().add(0, 3, 0, "Delete");
          popup.setOnMenuItemClickListener(
              item -> {
                if (listener == null) return true;
                int id = item.getItemId();
                if (id == 1) listener.onOpen(e);
                else if (id == 2) listener.onOpenNewTab(e);
                else listener.onDelete(e);
                return true;
              });
          popup.show();
        });
  }

  /** Favicon overlay: reset per bind (no stale bitmaps), load only for http/https rows. */
  private void bindFavicon(VH holder, RecentVisitsStore.Entry e) {
    holder.favicon.setVisibility(View.GONE);
    holder.favicon.setImageDrawable(null);
    holder.favicon.setTag(null);
    if (e.url == null || FaviconUrls.faviconUrlFor(e.url).isEmpty()) {
      return; // Internal/non-web row — letter avatar stays as fallback.
    }
    int avatarSizePx = Math.round(42 * holder.itemView.getResources().getDisplayMetrics().density);
    holder.favicon.setTag(e.url);
    FaviconLoader.loadAsync(e.url, holder.favicon, avatarSizePx);
  }

  @Override
  public void onViewRecycled(@NonNull VH holder) {
    // Stop a stale in-flight favicon from landing on a recycled row.
    holder.favicon.setImageDrawable(null);
    holder.favicon.setTag(null);
  }

  @Override
  public int getItemCount() {
    return items.size();
  }

  static final class VH extends RecyclerView.ViewHolder {
    final TextView avatar;
    final ImageView favicon;
    final TextView title;
    final TextView domain;
    final ImageButton menu;

    VH(View itemView) {
      super(itemView);
      avatar = itemView.findViewById(R.id.recent_avatar);
      favicon = itemView.findViewById(R.id.recent_favicon);
      title = itemView.findViewById(R.id.recent_title);
      domain = itemView.findViewById(R.id.recent_domain);
      menu = itemView.findViewById(R.id.recent_menu);
    }
  }

  /** Helper to open a URL in a new browser tab (new activity instance). */
  public static void openNewTab(android.content.Context context, String url) {
    if (context == null || url == null || url.trim().isEmpty()) return;
    Intent i = new Intent(context, DappBrowserActivity.class);
    i.putExtra("url", url.trim());
    if (!(context instanceof android.app.Activity)) {
      i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }
    try {
      context.startActivity(i);
    } catch (Exception ignored) {
      // No-op: caller already validates; never crash startpage for this.
    }
  }
}
