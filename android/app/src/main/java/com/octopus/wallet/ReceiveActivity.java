package com.octopus.wallet;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;

public class ReceiveActivity extends BaseTxActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_receive);
        setupToolbar(R.id.tx_toolbar, "Receive");

        String address = getIntent().getStringExtra("address");
        if (address == null) {
            address = "";
        }

        ImageView qrImage = findViewById(R.id.receive_qr_image);
        TextView addressText = findViewById(R.id.receive_address_text);
        addressText.setText(address);

        String finalAddress = address;
        findViewById(R.id.receive_copy_button).setOnClickListener(v -> copyAddress(finalAddress));

        if (!address.isEmpty()) {
            try {
                qrImage.setImageBitmap(generateQr(address, 720));
            } catch (Exception e) {
                Toast.makeText(this, "Failed to generate QR", Toast.LENGTH_LONG).show();
            }
        }
    }

    private Bitmap generateQr(String value, int size) throws Exception {
        BitMatrix matrix = new QRCodeWriter().encode(value, BarcodeFormat.QR_CODE, size, size);
        Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        for (int x = 0; x < size; x++) {
            for (int y = 0; y < size; y++) {
                bitmap.setPixel(x, y, matrix.get(x, y) ? 0xFF000000 : 0xFFFFFFFF);
            }
        }
        return bitmap;
    }

    private void copyAddress(String address) {
        ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        clipboard.setPrimaryClip(ClipData.newPlainText("Address", address));
        Toast.makeText(this, "Address copied", Toast.LENGTH_SHORT).show();
    }
}
