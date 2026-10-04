package com.octopus.wallet;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.widget.TextView;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class QrScanActivity extends BaseTxActivity {
    public static final String EXTRA_QR_TEXT = "qr_text";

    private PreviewView previewView;
    private final ExecutorService analyzerExecutor = Executors.newSingleThreadExecutor();
    private volatile boolean handled = false;

    private final ActivityResultLauncher<String> cameraPermissionLauncher =
            registerForActivityResult(new ActivityResultContracts.RequestPermission(), granted -> {
                if (granted) {
                    startCamera();
                } else {
                    showError("Camera permission is required to scan QR");
                    finish();
                }
            });

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_qr_scan);
        setupToolbar(R.id.qr_scan_toolbar, "Scan QR");

        previewView = findViewById(R.id.qr_preview);

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA);
        }
    }

    @Override
    protected void onDestroy() {
        analyzerExecutor.shutdown();
        super.onDestroy();
    }

    @androidx.annotation.OptIn(markerClass = androidx.camera.core.ExperimentalGetImage.class)
    private void startCamera() {
        ListenableFuture<ProcessCameraProvider> cameraProviderFuture = ProcessCameraProvider.getInstance(this);
        cameraProviderFuture.addListener(() -> {
            try {
                ProcessCameraProvider cameraProvider = cameraProviderFuture.get();
                Preview preview = new Preview.Builder().build();
                preview.setSurfaceProvider(previewView.getSurfaceProvider());

                ImageAnalysis analysis = new ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build();

                analysis.setAnalyzer(analyzerExecutor, imageProxy -> {
                    try {
                        if (handled) {
                            imageProxy.close();
                            return;
                        }
                        InputImage image = InputImage.fromMediaImage(
                                imageProxy.getImage(),
                                imageProxy.getImageInfo().getRotationDegrees()
                        );
                        BarcodeScanning.getClient()
                                .process(image)
                                .addOnSuccessListener(barcodes -> onBarcodes(barcodes))
                                .addOnCompleteListener(task -> imageProxy.close());
                    } catch (Exception e) {
                        imageProxy.close();
                    }
                });

                cameraProvider.unbindAll();
                cameraProvider.bindToLifecycle(
                        this,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis
                );
            } catch (Exception e) {
                showError("Unable to start camera scanner");
                finish();
            }
        }, ContextCompat.getMainExecutor(this));
    }

    private void onBarcodes(List<Barcode> barcodes) {
        if (barcodes == null || barcodes.isEmpty() || handled) {
            return;
        }
        for (Barcode barcode : barcodes) {
            String value = barcode.getRawValue();
            if (value == null || value.trim().isEmpty()) {
                continue;
            }
            handled = true;
            Intent data = new Intent();
            data.putExtra(EXTRA_QR_TEXT, value.trim());
            setResult(RESULT_OK, data);
            finish();
            return;
        }
    }
}
