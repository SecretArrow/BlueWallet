package com.octopus.wallet;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;
import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;
import java.util.ArrayList;
import java.util.List;

/**
 * Full-screen browser bookmarks manager (plan.txt § "Akses cepat ke bookmark"). Rows show favicon
 * (letter-avatar fallback), name and URL; tap opens the page in the dApp browser, the delete icon
 * removes after confirmation, and the toolbar menu offers a confirmed "Clear all".
 */
public class BookmarksActivity extends BaseTxActivity {

  private static final String TAG = "BookmarksActivity";

  private RecyclerView recycler;
  private TextView emptyText;
  private BookmarksAdapter adapter;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setContentView(R.layout.activity_bookmarks);
    setupToolbar(R.id.bookmarks_toolbar, "Bookmarks");

    recycler = findViewById(R.id.bookmarks_recycler);
    emptyText = findViewById(R.id.bookmarks_empty);
    adapter = new BookmarksAdapter();
    recycler.setLayoutManager(new LinearLayoutManager(this));
    recycler.setAdapter(adapter);
    refresh();
  }

  @Override
  protected void onResume() {
    super.onResume();
    refresh();
  }

  @Override
  public boolean onCreateOptionsMenu(Menu menu) {
    getMenuInflater().inflate(R.menu.bookmarks_toolbar_menu, menu);
    return true;
  }

  @Override
  public boolean onOptionsItemSelected(MenuItem item) {
    if (item.getItemId() == R.id.action_clear_bookmarks) {
      confirmClearAll();
      return true;
    }
    return super.onOptionsItemSelected(item);
  }

  private void refresh() {
    List<BookmarkStore.Bookmark> bookmarks;
    try {
      bookmarks = BookmarkStore.list(this);
    } catch (Exception e) {
      Log.w(TAG, "Bookmark list failed: " + e.getMessage());
      bookmarks = new ArrayList<>();
    }
    adapter.submit(bookmarks);
    emptyText.setVisibility(bookmarks.isEmpty() ? View.VISIBLE : View.GONE);
    recycler.setVisibility(bookmarks.isEmpty() ? View.GONE : View.VISIBLE);
  }

  private void openBookmark(String url) {
    if (url == null || url.trim().isEmpty()) return;
    try {
      Intent i = new Intent(this, DappBrowserActivity.class);
      i.putExtra("url", url.trim());
      startActivity(i);
    } catch (Exception e) {
      Log.w(TAG, "Open bookmark failed: " + e.getMessage());
      Toast.makeText(this, "Unable to open bookmark", Toast.LENGTH_SHORT).show();
    }
  }

  private void confirmDelete(BookmarkStore.Bookmark bookmark) {
    new AlertDialog.Builder(this)
        .setTitle("Remove bookmark")
        .setMessage(bookmark.url)
        .setPositiveButton(
            "Remove",
            (d, w) -> {
              BookmarkStore.remove(BookmarksActivity.this, bookmark.url);
              refresh();
              Toast.makeText(this, "Bookmark removed", Toast.LENGTH_SHORT).show();
            })
        .setNegativeButton("Cancel", null)
        .show();
  }

  private void confirmClearAll() {
    new AlertDialog.Builder(this)
        .setTitle("Clear all bookmarks")
        .setMessage("All bookmarks will be removed.")
        .setPositiveButton(
            "Clear",
            (d, w) -> {
              BookmarkStore.clearAll(BookmarksActivity.this);
              refresh();
              Toast.makeText(this, "Bookmarks cleared", Toast.LENGTH_SHORT).show();
            })
        .setNegativeButton("Cancel", null)
        .show();
  }

  /** Bookmark rows: favicon + name/url, tap opens, delete icon confirms. */
  private final class BookmarksAdapter extends RecyclerView.Adapter<BookmarksAdapter.VH> {

    private final List<BookmarkStore.Bookmark> items = new ArrayList<>();

    void submit(List<BookmarkStore.Bookmark> entries) {
      items.clear();
      if (entries != null) items.addAll(entries);
      notifyDataSetChanged();
    }

    @NonNull
    @Override
    public VH onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
      View v =
          LayoutInflater.from(parent.getContext()).inflate(R.layout.item_bookmark, parent, false);
      return new VH(v);
    }

    @Override
    public void onBindViewHolder(@NonNull VH holder, int position) {
      final BookmarkStore.Bookmark b = items.get(position);
      String name = b.name.isEmpty() ? b.url : b.name;
      holder.name.setText(name);
      holder.url.setText(b.url);
      String avatar = name.isEmpty() ? "?" : name.substring(0, 1).toUpperCase(java.util.Locale.US);
      holder.avatar.setText(avatar);

      // Favicon with letter-avatar fallback (same pattern as startpage).
      holder.favicon.setVisibility(View.GONE);
      holder.favicon.setImageDrawable(null);
      holder.favicon.setTag(null);
      if (!FaviconUrls.faviconUrlFor(b.url).isEmpty()) {
        int faviconSizePx =
            Math.round(42 * holder.itemView.getResources().getDisplayMetrics().density);
        holder.favicon.setTag(b.url);
        FaviconLoader.loadAsync(b.url, holder.favicon, faviconSizePx);
      }

      holder.itemView.setOnClickListener(v -> openBookmark(b.url));
      holder.delete.setOnClickListener(v -> confirmDelete(b));
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

    final class VH extends RecyclerView.ViewHolder {
      final TextView avatar;
      final ImageView favicon;
      final TextView name;
      final TextView url;
      final ImageButton delete;

      VH(View itemView) {
        super(itemView);
        avatar = itemView.findViewById(R.id.bookmark_avatar);
        favicon = itemView.findViewById(R.id.bookmark_favicon);
        name = itemView.findViewById(R.id.bookmark_name);
        url = itemView.findViewById(R.id.bookmark_url);
        delete = itemView.findViewById(R.id.bookmark_delete);
      }
    }
  }
}
