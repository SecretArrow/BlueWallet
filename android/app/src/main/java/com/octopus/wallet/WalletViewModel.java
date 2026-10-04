package com.octopus.wallet;

import android.app.Application;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.lifecycle.AndroidViewModel;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;

import org.json.JSONObject;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * MVVM ViewModel for wallet state.
 *
 * Owns the data-loading lifecycle so Activities/Fragments survive
 * configuration changes (rotation, theme switch) without re-fetching.
 *
 * Current status: provides the foundation for an incremental migration.
 * Activities can begin adopting individual LiveData fields while the rest
 * of the UI is still updated imperatively.
 *
 * Usage example in an Activity or Fragment:
 * <pre>
 *   WalletViewModel vm = new ViewModelProvider(this).get(WalletViewModel.class);
 *   vm.getBalanceSummary().observe(this, summary -> {
 *       totalBalanceText.setText(WalletRepository.formatOct(summary.totalRaw) + " OCT");
 *   });
 *   vm.loadBalance(rpcUrl, address);
 * </pre>
 */
public class WalletViewModel extends AndroidViewModel {

    private final WalletRepository repository;
    private final ExecutorService  executor = Executors.newFixedThreadPool(2);
    private final Handler          mainHandler = new Handler(Looper.getMainLooper());

    // ── Observable state ───────────────────────────────────────────────────

    private final MutableLiveData<WalletRepository.BalanceSummary> balanceSummary =
            new MutableLiveData<>();

    private final MutableLiveData<String> walletAddress    = new MutableLiveData<>();
    private final MutableLiveData<String> rpcUrl           = new MutableLiveData<>();
    private final MutableLiveData<Boolean> isLoading       = new MutableLiveData<>(false);
    private final MutableLiveData<String>  errorMessage    = new MutableLiveData<>();
    private final MutableLiveData<Long>    recommendedFee  = new MutableLiveData<>(1000L);

    // ── Constructor ────────────────────────────────────────────────────────

    public WalletViewModel(@NonNull Application application) {
        super(application);
        repository = new WalletRepository(application);
    }

    // ── Exposed LiveData ───────────────────────────────────────────────────

    public LiveData<WalletRepository.BalanceSummary> getBalanceSummary() { return balanceSummary; }
    public LiveData<String>  getWalletAddress()  { return walletAddress;  }
    public LiveData<String>  getRpcUrl()         { return rpcUrl;          }
    public LiveData<Boolean> getIsLoading()      { return isLoading;       }
    public LiveData<String>  getErrorMessage()   { return errorMessage;    }
    public LiveData<Long>    getRecommendedFee() { return recommendedFee;  }

    // ── Actions ────────────────────────────────────────────────────────────

    /**
     * Initialise wallet context from the native layer.
     * Posts walletAddress and rpcUrl on success, errorMessage on failure.
     */
    public void initWalletContext() {
        executor.execute(() -> {
            WalletRepository.Result<JSONObject> result = repository.getWalletInfo();
            if (!result.isSuccess()) {
                mainHandler.post(() -> errorMessage.setValue(result.getError()));
                return;
            }
            JSONObject info = result.getValue();
            String addr = info.optString("address", "");
            String rpc  = info.optString("rpc_url", UrlSecurityValidator.DEFAULT_RPC);
            mainHandler.post(() -> {
                walletAddress.setValue(addr);
                rpcUrl.setValue(rpc);
            });
        });
    }

    /**
     * Loads the balance for the current wallet.
     * Updates balanceSummary (and errorMessage on failure).
     */
    public void loadBalance(String rpc, String address) {
        if (rpc == null || address == null) return;
        mainHandler.post(() -> isLoading.setValue(true));
        executor.execute(() -> {
            WalletRepository.Result<WalletRepository.BalanceSummary> result =
                    repository.fetchBalance(rpc, address);
            mainHandler.post(() -> {
                isLoading.setValue(false);
                if (result.isSuccess()) {
                    balanceSummary.setValue(result.getValue());
                } else {
                    errorMessage.setValue(result.getError());
                }
            });
        });
    }

    /**
     * Fetches the recommended fee and updates the recommendedFee LiveData.
     */
    public void loadRecommendedFee(String rpc) {
        if (rpc == null) return;
        executor.execute(() -> {
            long fee = repository.fetchRecommendedFee(rpc, "standard", 1000L);
            mainHandler.post(() -> recommendedFee.setValue(fee));
        });
    }

    @Override
    protected void onCleared() {
        super.onCleared();
        executor.shutdown();
    }
}
