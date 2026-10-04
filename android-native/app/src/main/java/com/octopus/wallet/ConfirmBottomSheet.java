package com.octopus.wallet;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.google.android.material.bottomsheet.BottomSheetDialogFragment;
import com.google.android.material.button.MaterialButton;

/**
 * Reusable BottomSheetDialogFragment for transaction and action confirmations.
 *
 * Replaces the pattern of launching {@link ConfirmActionActivity} as a new Activity
 * for in-context confirmations. This is much faster and keeps the user in context.
 *
 * Usage:
 * <pre>
 *   ConfirmBottomSheet.newInstance(
 *       "Send Transaction",
 *       "Send 1.5 OCT to oct1abc...xyz?\nFee: 0.003 OCT",
 *       "Confirm", "Cancel",
 *       () -> launchTransaction(),
 *       () -> {}  // cancelled
 *   ).show(getSupportFragmentManager(), "confirm");
 * </pre>
 */
public class ConfirmBottomSheet extends BottomSheetDialogFragment {

    private static final String ARG_TITLE    = "title";
    private static final String ARG_MESSAGE  = "message";
    private static final String ARG_POSITIVE = "positive";
    private static final String ARG_NEGATIVE = "negative";

    /** Listener for confirm / cancel outcomes. */
    public interface OnResultListener {
        void onConfirm();
        void onCancel();
    }

    private OnResultListener listener;

    public static ConfirmBottomSheet newInstance(
            String title,
            String message,
            String positiveText,
            String negativeText,
            OnResultListener listener) {

        ConfirmBottomSheet sheet = new ConfirmBottomSheet();
        sheet.listener = listener;
        Bundle args = new Bundle();
        args.putString(ARG_TITLE,    title    != null ? title    : "Confirm");
        args.putString(ARG_MESSAGE,  message  != null ? message  : "");
        args.putString(ARG_POSITIVE, positiveText != null ? positiveText : "Confirm");
        args.putString(ARG_NEGATIVE, negativeText != null ? negativeText : "Cancel");
        sheet.setArguments(args);
        return sheet;
    }

    @Nullable
    @Override
    public View onCreateView(@NonNull LayoutInflater inflater,
                             @Nullable ViewGroup container,
                             @Nullable Bundle savedInstanceState) {
        return inflater.inflate(R.layout.bottom_sheet_confirm, container, false);
    }

    @Override
    public void onViewCreated(@NonNull View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);

        Bundle args = getArguments();
        String title    = args != null ? args.getString(ARG_TITLE, "Confirm") : "Confirm";
        String message  = args != null ? args.getString(ARG_MESSAGE, "")      : "";
        String positive = args != null ? args.getString(ARG_POSITIVE, "Confirm") : "Confirm";
        String negative = args != null ? args.getString(ARG_NEGATIVE, "Cancel")  : "Cancel";

        TextView titleView   = view.findViewById(R.id.confirm_sheet_title);
        TextView messageView = view.findViewById(R.id.confirm_sheet_message);
        MaterialButton positiveBtn = view.findViewById(R.id.confirm_sheet_positive);
        MaterialButton negativeBtn = view.findViewById(R.id.confirm_sheet_negative);

        if (titleView != null)   titleView.setText(title);
        if (messageView != null) messageView.setText(message);

        if (positiveBtn != null) {
            positiveBtn.setText(positive);
            positiveBtn.setOnClickListener(v -> {
                dismiss();
                if (listener != null) listener.onConfirm();
            });
        }

        if (negativeBtn != null) {
            if (negative.isEmpty()) {
                negativeBtn.setVisibility(View.GONE);
            } else {
                negativeBtn.setText(negative);
                negativeBtn.setOnClickListener(v -> {
                    dismiss();
                    if (listener != null) listener.onCancel();
                });
            }
        }
    }

    @Override
    public void onDestroyView() {
        super.onDestroyView();
        // Avoid memory leaks from lambda captures
        listener = null;
    }
}
